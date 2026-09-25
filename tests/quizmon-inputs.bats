#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    export INPUT="$BATS_TEST_TMPDIR/input.json"
    jq -n '{
      database_host: "database.example.test",
      database_passwords: {quizmon: "app-password", powersync_source: "source:@/password", powersync_storage: "storage-password"},
      dns_token: "dns-token",
      hyperdrive_id: ("c" * 32), backup_access_key: "backup-key", backup_secret_key: "backup-secret"
    }' > "$INPUT"
}

render() {
    jq -e --arg mode "$1" -f "$REPO_ROOT/clusters/shire/apps/quizmon/inputs.jq" "$INPUT"
}

@test "database inputs assign each CNPG role its own credential and exclude release secrets" {
    render database > "$BATS_TEST_TMPDIR/rendered.json"
    jq -e '
      length == 4 and
      ([.[] | select(.type == "kubernetes.io/basic-auth") | .stringData.username] | sort) ==
        ["powersync_source", "powersync_storage", "quizmon"] and
      all(.[]; .metadata.namespace == "quizmon") and
      all(.[]; .metadata.name != "quizmon-worker")
    ' "$BATS_TEST_TMPDIR/rendered.json"
    refute_file_contains "$BATS_TEST_TMPDIR/rendered.json" backup-secret
    refute_file_contains "$BATS_TEST_TMPDIR/rendered.json" quizmon-backup
}

@test "release inputs require TLS and preserve special characters in URI passwords" {
    render release > "$BATS_TEST_TMPDIR/rendered.json"
    jq -e '
      [.[] | select(.stringData.uri) | .stringData.uri] as $uris |
      ($uris | length) == 2 and all($uris[]; endswith("?sslmode=verify-full")) and
      any($uris[]; contains("source%3A%40%2Fpassword")) and
      ([.[] | select(.metadata.name == "quizmon-migration") |
        .stringData["migration-connection.json"] | fromjson] | .[0] |
        (has("version") | not) and .host == "database.example.test" and .database == "quizmon" and .user == "quizmon")
    ' "$BATS_TEST_TMPDIR/rendered.json"
    refute_file_contains "$BATS_TEST_TMPDIR/rendered.json" backup-secret
}

@test "unprovisioned Hyperdrive prevents release input generation" {
    jq '.hyperdrive_id = null' "$INPUT" > "$INPUT.next"
    mv "$INPUT.next" "$INPUT"
    run render release
    [ "$status" -ne 0 ]
    [[ "$output" == *"Hyperdrive must be provisioned"* ]]
}

@test "missing database credentials fail before producing a partial manifest" {
    jq 'del(.database_passwords.quizmon)' "$INPUT" > "$INPUT.next"
    mv "$INPUT.next" "$INPUT"
    run render database
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing database password"* ]]
}

prepare_refresh() {
    local source_root="$REPO_ROOT"
    setup_sops_fixture
    export FIXTURE="$BATS_TEST_TMPDIR/fixture"
    mkdir -p "$FIXTURE"
    cp -R "$source_root/scripts" "$FIXTURE/scripts"
    cp "$BATS_TEST_TMPDIR/.sops.yaml" "$FIXTURE/.sops.yaml"
    printf '    encrypted_regex: "^(data|stringData)$"\n' >> "$FIXTURE/.sops.yaml"
    mkdir -p "$FIXTURE/clusters/shire/apps/quizmon/"{database,release}/inputs
    cp "$source_root/clusters/shire/apps/quizmon/"{refresh-secrets.sh,inputs.jq} "$FIXTURE/clusters/shire/apps/quizmon/"
    (cd "$FIXTURE" && encrypt_fixture clusters/shire/apps/quizmon/database/inputs/quizmon-backup.sops.yaml \
        '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"quizmon-backup","namespace":"quizmon"},"stringData":{"ACCESS_KEY_ID":"scoped-backup-key","ACCESS_SECRET_KEY":"scoped-backup-secret"}}')
    cp "$FIXTURE/clusters/shire/apps/quizmon/database/inputs/quizmon-backup.sops.yaml" "$BATS_TEST_TMPDIR/original-backup"
    for mode in database release; do
        printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources: []\n' > \
            "$FIXTURE/clusters/shire/apps/quizmon/$mode/inputs/kustomization.yaml"
    done
    cat > "$FIXTURE/scripts/tofu-wrapper.sh" <<'SCRIPT'
#!/usr/bin/env bash
cat "$INPUT"
SCRIPT
}

@test "refresh encrypts real SOPS manifests and registers inputs without duplicates" {
    prepare_refresh
    bash "$FIXTURE/clusters/shire/apps/quizmon/refresh-secrets.sh" database
    bash "$FIXTURE/clusters/shire/apps/quizmon/refresh-secrets.sh" database
    local directory="$FIXTURE/clusters/shire/apps/quizmon/database/inputs"
    kubectl kustomize "$directory" > "$BATS_TEST_TMPDIR/rendered.yaml"
    for file in "$directory/"*.sops.yaml; do
        sops decrypt "$file" > /dev/null
    done
    yq -o=json -I=0 "$BATS_TEST_TMPDIR/rendered.yaml" | jq -se 'length == 5 and all(.[]; .kind == "Secret" and .sops.mac != null)'
    # Kustomize reorders fields. Flux also skips the whole-document MAC after rendering.
    # https://github.com/fluxcd/kustomize-controller/blob/v1.8.3/internal/decryptor/decryptor.go#L135-L139
    while IFS= read -r secret; do
        printf '%s\n' "$secret" | sops decrypt --ignore-mac --input-type json --output-type json /dev/stdin | jq -e '.stringData | length > 0' > /dev/null
    done < <(yq -o=json -I=0 "$BATS_TEST_TMPDIR/rendered.yaml")
    [ "$(yq '.resources | length' "$directory/kustomization.yaml")" -eq 5 ]
    refute_file_contains "$directory/quizmon-db-app.sops.yaml" app-password
    [ "$(stat -c '%a' "$directory/quizmon-db-app.sops.yaml")" = 600 ]
    cmp "$BATS_TEST_TMPDIR/original-backup" "$directory/quizmon-backup.sops.yaml"
}

@test "release refresh keeps credentials out of public runtime values and preserves files on invalid input" {
    prepare_refresh
    bash "$FIXTURE/clusters/shire/apps/quizmon/refresh-secrets.sh" release
    local directory="$FIXTURE/clusters/shire/apps/quizmon/release/inputs"
    [ "$(yq '.resources | length' "$directory/kustomization.yaml")" -eq 4 ]
    sops decrypt --output-type json "$directory/quizmon-migration.sops.yaml" | jq -e '.stringData["migration-connection.json"] | fromjson | .password == "app-password"'
    yq -o=json -I=0 '.data."values.yaml" | from_yaml' "$directory/runtime.yaml" |
        jq -e '.runtimeConfig.hyperdriveId == ("c" * 32) and
          (.inputs.migrationConnection.revision | test("^[a-f0-9]{64}$")) and
          (.inputs | has("workerSecrets") | not) and
          (.inputs | has("cloudflare") | not)'
    refute_file_contains "$directory/runtime.yaml" app-password
    cp "$directory/quizmon-migration.sops.yaml" "$BATS_TEST_TMPDIR/previous"
    jq 'del(.database_passwords.quizmon)' "$INPUT" > "$INPUT.next"
    mv "$INPUT.next" "$INPUT"
    run bash "$FIXTURE/clusters/shire/apps/quizmon/refresh-secrets.sh" release
    [ "$status" -ne 0 ]
    cmp "$BATS_TEST_TMPDIR/previous" "$directory/quizmon-migration.sops.yaml"
}

@test "database refresh cannot silently omit backup credentials" {
    prepare_refresh
    rm "$FIXTURE/clusters/shire/apps/quizmon/database/inputs/quizmon-backup.sops.yaml"
    run bash "$FIXTURE/clusters/shire/apps/quizmon/refresh-secrets.sh" database
    [ "$status" -eq 1 ]
    [[ "$output" == *'dedicated backup credentials first'* ]]
}
