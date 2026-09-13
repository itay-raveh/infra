#!/usr/bin/env bats

load test_helper/common

setup() {
    BOOTSTRAP_SOURCE_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    export BOOTSTRAP_SOURCE_ROOT
    REPO_ROOT="$BATS_TEST_TMPDIR/repo"
    export REPO_ROOT
    mkdir -p "$REPO_ROOT/bootstrap" "$REPO_ROOT/.github" \
        "$REPO_ROOT/clusters/shire/flux-system" \
        "$REPO_ROOT/clusters/shire/infrastructure/controllers"
    cp "$BOOTSTRAP_SOURCE_ROOT/bootstrap/bootstrap.sh" "$REPO_ROOT/bootstrap/"
    cp -R "$BOOTSTRAP_SOURCE_ROOT/scripts" "$REPO_ROOT/"
    cp -R "$BOOTSTRAP_SOURCE_ROOT/.github/rulesets" "$REPO_ROOT/.github/"
    cp "$BOOTSTRAP_SOURCE_ROOT/clusters/shire/infrastructure/controllers/talos-backup.yaml" \
        "$REPO_ROOT/clusters/shire/infrastructure/controllers/"
    export SOPS_AGE_KEY_FILE="$BATS_TEST_TMPDIR/identities.txt"
    export BOOTSTRAP_SSH_KEY_DIR="$BATS_TEST_TMPDIR/ssh"
    export BOOTSTRAP_CALLS="$BATS_TEST_TMPDIR/calls"
    unset SOPS_AGE_KEY SOPS_AGE_KEY_CMD
    printf '# existing identity reference\n' > "$SOPS_AGE_KEY_FILE"
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
        -out "$BATS_TEST_TMPDIR/app.pem" 2>/dev/null
    cat > "$BATS_TEST_TMPDIR/input" <<'EOF'
fixture-hcloud
fixture-s3-id
fixture-s3-secret
fixture-cloudflare-zone
fixture-cloudflare-account
primary@example.invalid
recovery-one@example.invalid
recovery-two@example.invalid
fixture-tailscale-id
fixture-tailscale-secret
123
fixture-upload-id
fixture-sentry
456
789
EOF
    printf '%s\n\n\n' "$BATS_TEST_TMPDIR/app.pem" >> "$BATS_TEST_TMPDIR/input"
    setup_fakebin
    cat > "$FAKEBIN/age-plugin-yubikey" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'age-plugin-yubikey %s\n' "$*" >> "$BOOTSTRAP_CALLS"
counter_file="$BATS_TEST_TMPDIR/hardware-count"
counter=0
[[ ! -f "$counter_file" ]] || counter=$(cat "$counter_file")
if [[ "$1" == --generate ]]; then
    [[ ${FAIL_HARDWARE:-0} != 1 ]] || exit 9
    counter=$((counter + 1))
    printf '%s' "$counter" > "$counter_file"
    age-keygen -o "$BATS_TEST_TMPDIR/hardware-$counter" 2>/dev/null
    cat "$BATS_TEST_TMPDIR/hardware-$counter"
else
    age-keygen -y "$BATS_TEST_TMPDIR/hardware-$counter"
fi
EOF
    cat > "$FAKEBIN/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh-keygen %s\n' "$*" >> "$BOOTSTRAP_CALLS"
[[ ${FAIL_SSH:-0} != 1 ]] || exit 8
while (($#)); do
    if [[ "$1" == -f ]]; then
        printf 'fixture handle' > "$2"
        printf 'fixture public key' > "$2.pub"
        break
    fi
    shift
done
EOF
    cat > "$FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >> "$BOOTSTRAP_CALLS"
if [[ "$1 $2" == 'repo view' ]]; then
    printf 'example/infra\n'
elif [[ "$1 $2" == 'secret set' ]]; then
    cat > "$BATS_TEST_TMPDIR/github-$3"
fi
EOF
    cat > "$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$BOOTSTRAP_CALLS"
EOF
    cat > "$FAKEBIN/wg" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == genkey ]]; then
    openssl rand -base64 32
else
    cat >/dev/null
    printf 'fixture-wireguard-public\n'
fi
EOF
    chmod +x "$FAKEBIN/"*
    cd "$REPO_ROOT" || return
}

@test "bootstrap creates decryptable credentials for the OpenTofu and Flux consumers" {
    run bash bootstrap/bootstrap.sh < "$BATS_TEST_TMPDIR/input"
    [ "$status" -eq 0 ]
    [[ "$output" != *fixture-s3-secret* ]]
    [[ "$output" != *'BEGIN PRIVATE KEY'* ]]
    assert_file_contains "$SOPS_AGE_KEY_FILE" '# existing identity reference'
    [ "$(stat -c '%a' "$SOPS_AGE_KEY_FILE")" = 600 ]

    while IFS= read -r variable; do
        [[ "$variable" != ssh_public_key_path ]] || continue
        if ! bash scripts/sops-exec.sh secrets/state.sops.yaml secrets/tofu.sops.yaml \
            secrets/wireguard.sops.yaml -- sh -c 'test -n "$(printenv "$1")"' \
            sh "TF_VAR_$variable"; then
            printf 'missing bootstrap variable: %s\n' "$variable" >&2
            return 1
        fi
    done < <(awk '/^variable / {gsub(/"/, "", $2); print $2}' \
        "$BOOTSTRAP_SOURCE_ROOT/tofu/variables.tf")
    sops decrypt --output-type json secrets/tofu.sops.yaml | jq -e '
        .SENTRY_AUTH_TOKEN == "fixture-sentry" and
        .TAILSCALE_OAUTH_CLIENT_SECRET == "fixture-tailscale-secret" and
        .TF_VAR_cloudflare_proton_email == "recovery-two@example.invalid"
    ' >/dev/null
    sops decrypt --output-type json clusters/shire/flux-system/flux-github-app.sops.yaml | jq -e '
        .metadata == {namespace: "flux-system", name: "flux-github-app"} and
        .stringData.githubAppID == "456" and
        .stringData.githubAppInstallationID == "789" and
        (.stringData | has("githubAppInstallationOwner") | not)
    ' >/dev/null
    sops decrypt --output-type json clusters/shire/flux-system/flux-github-app.sops.yaml |
        jq -r .stringData.githubAppPrivateKey | cmp - "$BATS_TEST_TMPDIR/app.pem"
    cmp "$BATS_TEST_TMPDIR/github-FLUX_APP_PRIVATE_KEY" "$BATS_TEST_TMPDIR/app.pem"
    [ "$(cat "$BATS_TEST_TMPDIR/github-FLUX_APP_ID")" = 456 ]
    assert_file_contains "$BOOTSTRAP_CALLS" '--repo example/infra'
    refute_file_contains "$BOOTSTRAP_CALLS" 'BEGIN PRIVATE KEY'
}

@test "bootstrap connects the etcd backup recipient and restricts both private keys to recovery identities" {
    run bash bootstrap/bootstrap.sh < "$BATS_TEST_TMPDIR/input"
    [ "$status" -eq 0 ]
    local etcd_recipient cluster_recipient
    etcd_recipient=$(sops decrypt bootstrap/etcd-backup-age-key.sops.txt | age-keygen -y)
    cluster_recipient=$(sops decrypt bootstrap/cluster-age-key.sops.txt | age-keygen -y)
    [ "$etcd_recipient" != "$cluster_recipient" ]
    [ "$(yq -r 'select(.kind == "CronJob") |
        .spec.jobTemplate.spec.template.spec.containers[].env[] |
        select(.name == "AGE_X25519_PUBLIC_KEY").value' \
        clusters/shire/infrastructure/controllers/talos-backup.yaml)" = "$etcd_recipient" ]
    for file in bootstrap/*.sops.txt; do
        [ "$(stat -c '%a' "$file")" = 600 ]
        jq -e --arg cluster "$cluster_recipient" '
            .sops.age | length == 2 and all(.recipient != $cluster)
        ' "$file" >/dev/null
    done
    sops decrypt bootstrap/cluster-age-key.sops.txt > "$BATS_TEST_TMPDIR/cluster-key"
    SOPS_AGE_KEY_FILE="$BATS_TEST_TMPDIR/cluster-key" \
        sops decrypt clusters/shire/flux-system/flux-github-app.sops.yaml >/dev/null
    run env SOPS_AGE_KEY_FILE="$BATS_TEST_TMPDIR/cluster-key" \
        sops decrypt bootstrap/etcd-backup-age-key.sops.txt
    [ "$status" -ne 0 ]
}

@test "bootstrap refuses existing recovery material before touching hardware or GitHub" {
    printf 'previous ciphertext' > bootstrap/etcd-backup-age-key.sops.txt
    run bash bootstrap/bootstrap.sh < "$BATS_TEST_TMPDIR/input"
    [ "$status" -ne 0 ]
    [ "$(cat bootstrap/etcd-backup-age-key.sops.txt)" = 'previous ciphertext' ]
    [ ! -e "$BOOTSTRAP_CALLS" ]
}

@test "bootstrap rejects empty credentials before generating hardware keys" {
    run bash bootstrap/bootstrap.sh <<< ''
    [ "$status" -ne 0 ]
    [[ "$output" == *'cannot be empty'* ]]
    refute_file_contains "$BOOTSTRAP_CALLS" age-plugin-yubikey
    [ ! -e .sops.yaml ]
}

@test "bootstrap stops when hardware generation fails inside command substitution" {
    export FAIL_HARDWARE=1
    run bash bootstrap/bootstrap.sh < "$BATS_TEST_TMPDIR/input"
    [ "$status" -eq 9 ]
    refute_file_contains "$BOOTSTRAP_CALLS" 'ssh-keygen '
    [ ! -e .sops.yaml ]
    [ ! -e secrets ]
}

@test "bootstrap stops when SSH key generation fails" {
    export FAIL_SSH=1
    run bash bootstrap/bootstrap.sh < "$BATS_TEST_TMPDIR/input"
    [ "$status" -eq 8 ]
    refute_file_contains "$BOOTSTRAP_CALLS" 'gh ssh-key add'
    [ ! -e .sops.yaml ]
}
