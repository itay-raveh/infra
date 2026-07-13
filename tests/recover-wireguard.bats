#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    setup_fakebin

    export TEST_SERVER_PRIVATE=server-private
    export TEST_WORKSTATION_PUBLIC=workstation-public
    export TEST_TALOS_CALLS="$BATS_TEST_TMPDIR/talosctl.log"
    export TEST_MISE_CALLS="$BATS_TEST_TMPDIR/mise.log"
    export TEST_SLEEP_CALLS="$BATS_TEST_TMPDIR/sleep.log"
    export TEST_PATCH_CAPTURE="$BATS_TEST_TMPDIR/patch.yaml"

    cat > "$FAKEBIN/sops" <<'EOF'
#!/usr/bin/env bash
printf 'TF_VAR_wireguard_server_private_key=%q\n' "$TEST_SERVER_PRIVATE"
printf 'TF_VAR_wireguard_workstation_public_key=%q\n' "$TEST_WORKSTATION_PUBLIC"
EOF

    cat > "$FAKEBIN/tofu" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
    public_ipv4)
        printf '203.0.113.10'
        ;;
    private_ipv4)
        if [[ "${TEST_PRIVATE_OUTPUT_MODE:-present}" == missing ]]; then
            exit 1
        fi
        printf '%s' "${TEST_PRIVATE_IPV4:-10.0.1.42}"
        ;;
    talosconfig)
        printf 'context: test\n'
        ;;
    *)
        exit 1
        ;;
esac
EOF

    cat > "$FAKEBIN/mise" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_MISE_CALLS"
EOF

    cat > "$FAKEBIN/talosctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_TALOS_CALLS"
if [[ "$*" == *'patch machineconfig'* ]]; then
    for argument in "$@"; do
        if [[ "$argument" == @* ]]; then
            cp "${argument#@}" "$TEST_PATCH_CAPTURE"
        fi
    done
fi
if [[ "$*" == *' version'* ]]; then
    [[ "${TEST_PRIVATE_REACHABLE:-1}" == 1 ]]
fi
EOF

    cat > "$FAKEBIN/timeout" <<'EOF'
#!/usr/bin/env bash
shift
exec "$@"
EOF

    cat > "$FAKEBIN/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_SLEEP_CALLS"
EOF

    make_executable "$FAKEBIN/sops"
    make_executable "$FAKEBIN/tofu"
    make_executable "$FAKEBIN/mise"
    make_executable "$FAKEBIN/talosctl"
    make_executable "$FAKEBIN/timeout"
    make_executable "$FAKEBIN/sleep"
}

@test "persists the try patch only after the configured private endpoint responds" {
    run env TEST_PRIVATE_IPV4=10.0.1.42 bash scripts/recover-wireguard.sh

    [ "$status" -eq 0 ]
    assert_file_contains "$TEST_TALOS_CALLS" "--endpoints 203.0.113.10 --nodes 203.0.113.10 patch machineconfig"
    assert_file_contains "$TEST_TALOS_CALLS" "--mode try --timeout 5m"
    assert_file_contains "$TEST_TALOS_CALLS" "--endpoints 10.0.1.42 --nodes 10.0.1.42 version"
    assert_file_contains "$TEST_TALOS_CALLS" "--endpoints 10.0.1.42 --nodes 10.0.1.42 patch machineconfig"
    assert_file_contains "$TEST_TALOS_CALLS" "--mode no-reboot"
    assert_file_contains "$TEST_MISE_CALLS" "run wireguard:configure"
    assert_file_contains "$TEST_PATCH_CAPTURE" "kind: WireguardConfig"
    assert_file_contains "$TEST_PATCH_CAPTURE" "privateKey: $TEST_SERVER_PRIVATE"
    assert_file_contains "$TEST_PATCH_CAPTURE" "publicKey: $TEST_WORKSTATION_PUBLIC"
}

@test "fails after bounded probes without persisting an unreachable patch" {
    run env TEST_PRIVATE_REACHABLE=0 WIREGUARD_VERIFY_ATTEMPTS=2 WIREGUARD_VERIFY_TIMEOUT=1 WIREGUARD_VERIFY_DELAY=0 bash scripts/recover-wireguard.sh

    [ "$status" -ne 0 ]
    [[ "$output" == *"Talos will roll back the try patch automatically."* ]]
    [ "$(grep -Fc ' version' "$TEST_TALOS_CALLS")" -eq 2 ]
    refute_file_contains "$TEST_TALOS_CALLS" "--mode no-reboot"
}

@test "uses the bootstrap private address when state has no private output" {
    run env TEST_PRIVATE_OUTPUT_MODE=missing bash scripts/recover-wireguard.sh

    [ "$status" -eq 0 ]
    assert_file_contains "$TEST_TALOS_CALLS" "--endpoints 10.0.1.101 --nodes 10.0.1.101 version"
    assert_file_contains "$TEST_TALOS_CALLS" "--endpoints 10.0.1.101 --nodes 10.0.1.101 patch machineconfig"
}
