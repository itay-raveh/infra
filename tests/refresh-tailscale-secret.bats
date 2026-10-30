#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_script_repo
    setup_fakebin
    export TEST_TOFU_CALLS="$BATS_TEST_TMPDIR/tofu.log"
    cat > "$FAKEBIN/sops" <<'EOF'
#!/usr/bin/env bash
export TF_VAR_encryption_passphrase=test AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
exec /bin/sh -c "$4"
EOF
    cat > "$FAKEBIN/tofu" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_TOFU_CALLS"
if [[ "${TEST_MISSING_SECRET:-0}" == 1 ]]; then
    printf '{"tailscale_operator_oauth_client_id":{"value":"client-id"}}'
else
    printf '{"tailscale_operator_oauth_client_id":{"value":"client-id"},"tailscale_operator_oauth_client_secret":{"value":"client-secret"}}'
fi
exit "${TEST_TOFU_STATUS:-0}"
EOF
    make_executable "$FAKEBIN/sops"
    make_executable "$FAKEBIN/tofu"
}

@test "renders both OAuth fields from a single state read" {
    run bash scripts/refresh-tailscale-secret.sh --render
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '
        .metadata == {namespace: "tailscale", name: "operator-oauth"} and
        (.data.client_id | @base64d) == "client-id" and
        (.data.client_secret | @base64d) == "client-secret"
    ' >/dev/null
    [ "$(wc -l < "$TEST_TOFU_CALLS")" -eq 1 ]
}

@test "fails when either state output is missing" {
    run env TEST_MISSING_SECRET=1 bash scripts/refresh-tailscale-secret.sh --render
    [ "$status" -ne 0 ]
}

@test "propagates failure even when OpenTofu emitted valid JSON" {
    run env TEST_TOFU_STATUS=9 bash scripts/refresh-tailscale-secret.sh --render
    [ "$status" -eq 9 ]
}
