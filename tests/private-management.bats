#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
}

@test "uses direct private control-plane endpoints without a single-node VIP" {
    grep -Eq 'bootstrap_endpoint_mode[[:space:]]*=[[:space:]]*"private_ip"' tofu/main.tf
    grep -Eq 'kubeconfig_endpoint_mode[[:space:]]*=[[:space:]]*"private_ip"' tofu/main.tf
    grep -Eq 'talosconfig_endpoints_mode[[:space:]]*=[[:space:]]*"private_ip"' tofu/main.tf
    grep -Eq 'enable_alias_ip[[:space:]]*=[[:space:]]*false' tofu/main.tf
}

@test "defines native Talos WireGuard and its UDP firewall rule" {
    grep -Eq 'kind[[:space:]]*=[[:space:]]*"WireguardConfig"' tofu/main.tf
    grep -Eq 'name[[:space:]]*=[[:space:]]*"wg0"' tofu/main.tf
    grep -Eq 'listenPort[[:space:]]*=[[:space:]]*51820' tofu/main.tf
    grep -Eq 'protocol[[:space:]]*=[[:space:]]*"udp"' tofu/main.tf
    grep -Eq 'port[[:space:]]*=[[:space:]]*"51820"' tofu/main.tf
}

@test "does not expose management through public or Tailnet-wide API rules" {
    run grep -En 'firewall_(talos|kube)_api_source|100\.64\.0\.0/10' tofu/main.tf tofu/variables.tf

    [ "$status" -eq 1 ]
}

@test "does not install or authenticate host Tailscale" {
    run grep -En 'siderolabs/tailscale|tailscale_auth_key|TF_VAR_tailscale_auth_key' tofu/talos.tf tofu/variables.tf bootstrap/bootstrap.sh mise.toml

    [ "$status" -eq 1 ]
}

@test "keeps bootstrap and rebuild wired to WireGuard management" {
    grep -Eq 'WIREGUARD_WORKSTATION_PRIVATE_KEY' bootstrap/bootstrap.sh
    grep -Eq 'wg genkey' bootstrap/bootstrap.sh
    grep -Eq 'module\.talos\.hcloud_primary_ip\.control_plane_ipv4' scripts/rebuild.sh
    grep -Eq 'wireguard:configure' scripts/rebuild.sh
    grep -Eq '\[tasks\."wireguard:configure"\]' mise.toml
    grep -Eq '\[tasks\."wireguard:recover"\]' mise.toml
}
