#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_script_repo
    setup_fakebin
    export TEST_SOPS_CALLS="$BATS_TEST_TMPDIR/sops.log"
    cat > "$FAKEBIN/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$3" >> "$TEST_SOPS_CALLS"
if [[ "${TEST_DECRYPT_FAIL:-0}" == 1 ]]; then exit 23; fi
while IFS= read -r key; do
    export "$key=test"
done < <(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*):.*/\1/p' "$3")
exec /bin/sh -c "$4"
EOF
    cat > "$FAKEBIN/tofu" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$TF_VAR_encryption_passphrase" == test && "$AWS_ACCESS_KEY_ID" == test && "$AWS_SECRET_ACCESS_KEY" == test ]]
[[ -z "${WIREGUARD_WORKSTATION_PRIVATE_KEY+x}" ]]
if [[ "$2" == output ]]; then
    [[ -z "${TF_VAR_cloudflare_api_token+x}" && -z "${TF_VAR_hcloud_token+x}" && -z "${TF_VAR_wireguard_server_private_key+x}" ]]
else
    [[ "$TF_VAR_cloudflare_api_token" == test && "$TF_VAR_hcloud_token" == test && "$TF_VAR_wireguard_server_private_key" == test ]]
fi
printf invoked
EOF
    make_executable "$FAKEBIN/sops"
    make_executable "$FAKEBIN/tofu"
}

@test "state output loads only state credentials" {
    run bash scripts/tofu-wrapper.sh output -raw public_ipv4
    [ "$status" -eq 0 ]
    [ "$output" = invoked ]
    [ "$(cat "$TEST_SOPS_CALLS")" = secrets/state.sops.yaml ]
}

@test "planning loads provider and server credentials without the workstation private key" {
    run bash scripts/tofu-wrapper.sh plan
    [ "$status" -eq 0 ]
    [ "$output" = invoked ]
    [ "$(wc -l < "$TEST_SOPS_CALLS")" -eq 3 ]
}

@test "does not invoke OpenTofu after decryption failure" {
    run env TEST_DECRYPT_FAIL=1 bash scripts/tofu-wrapper.sh output -raw public_ipv4
    [ "$status" -eq 23 ]
    [ "$output" != invoked ]
}
