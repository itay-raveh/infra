#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    export INPUT="$BATS_TEST_TMPDIR/input.json"
    export WORKER="$BATS_TEST_TMPDIR/worker.json"
    jq -n '{
      database_host: "database.example.test",
      database_passwords: {quizmon: "app-password", powersync_source: "source:@/password", powersync_storage: "storage-password"},
      auth_secret: ("a" * 64), dns_token: "dns-token",
      cloudflare: {accountId: ("b" * 32), token: "deployment-token"},
      hyperdrive_id: ("c" * 32), backup_access_key: "backup-key", backup_secret_key: "backup-secret"
    }' > "$INPUT"
    jq -n '{VAPID_PRIVATE_KEY: ("d" * 43)}' > "$WORKER"
}

render() {
    jq -e --arg mode "$1" --slurpfile worker "$WORKER" -f "$REPO_ROOT/scripts/quizmon-inputs.jq" "$INPUT"
}

@test "database inputs assign each CNPG role its own credential and exclude release secrets" {
    render database > "$BATS_TEST_TMPDIR/rendered.json"
    jq -e '
      .items | length == 5 and
      ([.[] | select(.type == "kubernetes.io/basic-auth") | .stringData.username] | sort) ==
        ["powersync_source", "powersync_storage", "quizmon"] and
      all(.[]; .metadata.namespace == "quizmon") and
      all(.[]; .metadata.name != "quizmon-worker")
    ' "$BATS_TEST_TMPDIR/rendered.json"
    refute_file_contains "$BATS_TEST_TMPDIR/rendered.json" deployment-token
}

@test "release inputs require TLS and preserve special characters in URI passwords" {
    render release > "$BATS_TEST_TMPDIR/rendered.json"
    jq -e '
      [.items[] | select(.stringData.uri) | .stringData.uri] as $uris |
      ($uris | length) == 2 and all($uris[]; endswith("?sslmode=verify-full")) and
      any($uris[]; contains("source%3A%40%2Fpassword")) and
      ([.items[] | select(.metadata.name == "quizmon-migration") |
        .stringData["migration-connection.json"] | fromjson] | .[0] |
        .host == "database.example.test" and .database == "quizmon" and .user == "quizmon")
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

@test "missing reminder key cannot silently replace existing subscriptions" {
    printf '{}\n' > "$WORKER"
    run render release
    [ "$status" -ne 0 ]
    [[ "$output" == *"existing VAPID_PRIVATE_KEY"* ]]
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
    bash "$FIXTURE/scripts/refresh-quizmon-secrets.sh" database
    bash "$FIXTURE/scripts/refresh-quizmon-secrets.sh" database
    local directory="$FIXTURE/clusters/shire/apps/quizmon/database/inputs"
    sops decrypt --output-type json "$directory/generated.sops.yaml" | jq -e '.items | length == 5'
    [ "$(yq '.resources | length' "$directory/kustomization.yaml")" -eq 1 ]
    refute_file_contains "$directory/generated.sops.yaml" app-password
    [ "$(stat -c '%a' "$directory/generated.sops.yaml")" = 600 ]
}

@test "release refresh keeps credentials out of public runtime values and preserves files on invalid input" {
    prepare_refresh
    bash "$FIXTURE/scripts/refresh-quizmon-secrets.sh" release "$WORKER"
    local directory="$FIXTURE/clusters/shire/apps/quizmon/release/inputs"
    sops decrypt --output-type json "$directory/generated.sops.yaml" | jq -e '.items | length == 5'
    jq -e '.data["values.yaml"] | fromjson | .runtimeConfig.hyperdriveId == ("c" * 32) and
      (.inputs.workerSecrets.revision | test("^[a-f0-9]{64}$"))' "$directory/runtime.yaml"
    refute_file_contains "$directory/runtime.yaml" deployment-token
    refute_file_contains "$directory/runtime.yaml" app-password
    cp "$directory/generated.sops.yaml" "$BATS_TEST_TMPDIR/previous"
    printf '{}\n' > "$WORKER"
    run bash "$FIXTURE/scripts/refresh-quizmon-secrets.sh" release "$WORKER"
    [ "$status" -ne 0 ]
    cmp "$BATS_TEST_TMPDIR/previous" "$directory/generated.sops.yaml"
}
