#!/usr/bin/env bats
load test_helper/common

setup() {
    setup_script_repo
    setup_fakebin
    export INFRA_CONFIG_ROOT="$BATS_TEST_TMPDIR/configs"
    mkdir -p "$INFRA_CONFIG_ROOT/.kube" "$INFRA_CONFIG_ROOT/.talos"
    printf 'original kubeconfig' > "$INFRA_CONFIG_ROOT/.kube/config"
    printf 'original talosconfig' > "$INFRA_CONFIG_ROOT/.talos/config"
    export CONFIG_FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    cat > "$FAKEBIN/tofu" <<'SH'
#!/usr/bin/env bash
case "$4" in
    kubeconfig)
        case "${BAD_KUBECONFIG:-valid}" in
            malformed) printf '[' ;;
            empty) printf '{}' ;;
            *) cat "$CONFIG_FIXTURES/kubeconfig.yaml" ;;
        esac
        ;;
    talosconfig)
        if [[ ${BAD_TALOSCONFIG:-0} == 1 ]]; then printf '['; else cat "$CONFIG_FIXTURES/talosconfig.yaml"; fi
        [[ ${FAIL_OUTPUT:-0} != 1 ]] || exit 19
        ;;
    private_ipv4) printf '10.0.1.101' ;;
    *) exit 1 ;;
esac
SH
    cat > "$FAKEBIN/sops" <<'SH'
#!/usr/bin/env bash
exit 23
SH
    chmod +x "$FAKEBIN/"*
}

@test "refresh installs both complete client configs with private permissions" {
    run bash scripts/refresh-configs.sh --decrypted
    [ "$status" -eq 0 ]
    [ "$(stat -c '%a' "$INFRA_CONFIG_ROOT/.kube/config")" = 600 ]
    [ "$(stat -c '%a' "$INFRA_CONFIG_ROOT/.talos/config")" = 600 ]
    [ "$(kubectl --kubeconfig "$INFRA_CONFIG_ROOT/.kube/config" config current-context)" = fixture ]
    [ "$(yq '.contexts.fixture.nodes[0]' "$INFRA_CONFIG_ROOT/.talos/config")" = 10.0.1.101 ]
    [ "$(find "$INFRA_CONFIG_ROOT" -type f | wc -l)" -eq 2 ]
}

@test "partial state output cannot replace either existing client config" {
    run env FAIL_OUTPUT=1 bash scripts/refresh-configs.sh --decrypted
    [ "$status" -eq 19 ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.kube/config")" = 'original kubeconfig' ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.talos/config")" = 'original talosconfig' ]
    [ "$(find "$INFRA_CONFIG_ROOT" -type f | wc -l)" -eq 2 ]
}

@test "the real Talos parser rejects malformed config without replacing either file" {
    run env BAD_TALOSCONFIG=1 bash scripts/refresh-configs.sh --decrypted
    [ "$status" -ne 0 ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.kube/config")" = 'original kubeconfig' ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.talos/config")" = 'original talosconfig' ]
}

@test "the real Kubernetes parser rejects malformed config without replacing either file" {
    run env BAD_KUBECONFIG=malformed bash scripts/refresh-configs.sh --decrypted
    [ "$status" -ne 0 ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.kube/config")" = 'original kubeconfig' ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.talos/config")" = 'original talosconfig' ]
}

@test "decryption failure preserves existing client configs" {
    run bash scripts/refresh-configs.sh
    [ "$status" -eq 23 ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.kube/config")" = 'original kubeconfig' ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.talos/config")" = 'original talosconfig' ]
}

@test "an empty kubeconfig cannot replace working client configs" {
    run env BAD_KUBECONFIG=empty bash scripts/refresh-configs.sh --decrypted
    [ "$status" -ne 0 ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.kube/config")" = 'original kubeconfig' ]
    [ "$(cat "$INFRA_CONFIG_ROOT/.talos/config")" = 'original talosconfig' ]
}
