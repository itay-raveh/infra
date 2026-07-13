#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    setup_fakebin

    export TEST_SERVER_PRIVATE=server-private
    export TEST_SERVER_PUBLIC=server-public
    export TEST_WORKSTATION_PRIVATE=workstation-private
    export TEST_WORKSTATION_PUBLIC=workstation-public
    export TEST_CONFIG_CAPTURE="$BATS_TEST_TMPDIR/shire.conf"
    export TEST_CALLS="$BATS_TEST_TMPDIR/calls.log"

    cat > "$FAKEBIN/sops" <<'EOF'
#!/usr/bin/env bash
printf 'TF_VAR_wireguard_server_private_key=%q\n' "$TEST_SERVER_PRIVATE"
printf 'TF_VAR_wireguard_workstation_public_key=%q\n' "$TEST_WORKSTATION_PUBLIC"
if [[ "${TEST_MISSING_WORKSTATION_PRIVATE:-0}" != 1 ]]; then
    printf 'WIREGUARD_WORKSTATION_PRIVATE_KEY=%q\n' "$TEST_WORKSTATION_PRIVATE"
fi
EOF

    cat > "$FAKEBIN/tofu" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *'output -raw public_ipv4'* ]]; then
    printf '203.0.113.10'
    exit 0
fi
exit 1
EOF

    cat > "$FAKEBIN/wg" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    pubkey)
        cat >/dev/null
        printf '%s\n' "$TEST_SERVER_PUBLIC"
        ;;
    show)
        [[ "${TEST_INTERFACE_PRESENT:-0}" == 1 ]]
        ;;
    *)
        exit 1
        ;;
esac
EOF

    cat > "$FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_CALLS"
if [[ "${1:-}" == install && "${2:-}" == -d ]]; then
    exit 0
fi
if [[ "${1:-}" == install && "${2:-}" == -m ]]; then
    install -m "$3" "$4" "$TEST_CONFIG_CAPTURE"
    exit 0
fi
exec "$@"
EOF

    cat > "$FAKEBIN/wg-quick" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    make_executable "$FAKEBIN/sops"
    make_executable "$FAKEBIN/tofu"
    make_executable "$FAKEBIN/wg"
    make_executable "$FAKEBIN/sudo"
    make_executable "$FAKEBIN/wg-quick"
}

@test "writes a mode-600 configuration and activates a new interface" {
    run env TEST_INTERFACE_PRESENT=0 bash scripts/configure-wireguard.sh

    [ "$status" -eq 0 ]
    [ "$output" = "WireGuard interface shire is active." ]
    [ "$(stat -c '%a' "$TEST_CONFIG_CAPTURE")" = 600 ]
    assert_file_contains "$TEST_CONFIG_CAPTURE" "PrivateKey = $TEST_WORKSTATION_PRIVATE"
    assert_file_contains "$TEST_CONFIG_CAPTURE" "Address = 10.200.0.250/24"
    assert_file_contains "$TEST_CONFIG_CAPTURE" "PublicKey = $TEST_SERVER_PUBLIC"
    assert_file_contains "$TEST_CONFIG_CAPTURE" "Endpoint = 203.0.113.10:51820"
    assert_file_contains "$TEST_CONFIG_CAPTURE" "AllowedIPs = 10.200.0.0/24, 10.0.1.0/24"
    assert_file_contains "$TEST_CALLS" "wg-quick up shire"
    refute_file_contains "$TEST_CALLS" "wg-quick down shire"
}

@test "restarts an existing interface before bringing it up" {
    run env TEST_INTERFACE_PRESENT=1 bash scripts/configure-wireguard.sh

    [ "$status" -eq 0 ]
    down_line=$(grep -nF "wg-quick down shire" "$TEST_CALLS" | cut -d: -f1)
    up_line=$(grep -nF "wg-quick up shire" "$TEST_CALLS" | cut -d: -f1)
    [ "$down_line" -lt "$up_line" ]
}

@test "rejects missing decrypted workstation credentials before sudo" {
    run env TEST_MISSING_WORKSTATION_PRIVATE=1 bash scripts/configure-wireguard.sh

    [ "$status" -ne 0 ]
    [[ "$output" == *"missing WIREGUARD_WORKSTATION_PRIVATE_KEY"* ]]
    [ ! -e "$TEST_CALLS" ]
}
