#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

assert_contains() {
    local file=$1
    local pattern=$2
    local message=$3

    if ! grep -Eq "$pattern" "$file"; then
        printf 'FAIL: %s\n' "$message" >&2
        exit 1
    fi
}

assert_not_contains() {
    local path=$1
    local pattern=$2
    local message=$3

    if rg -q "$pattern" "$path"; then
        printf 'FAIL: %s\n' "$message" >&2
        exit 1
    fi
}

assert_contains tofu/main.tf 'version[[:space:]]*=[[:space:]]*"3\.4\.1"' \
    'hcloud-talos must be pinned to 3.4.1'
assert_contains tofu/locals.tf 'talos_version[[:space:]]*=[[:space:]]*"v1\.12\.8"' \
    'Talos must use the repaired 1.12 patch release'
assert_contains tofu/main.tf 'extraKernelArgs[[:space:]]*=[[:space:]]*\["talos\.platform=hcloud",[[:space:]]*"net\.ifnames=0"\]' \
    'the hcloud boot configuration must explicitly preserve eth0 and eth1 names'
assert_contains mise.toml 'talosctl[[:space:]]*=[[:space:]]*"1\.12\.8"' \
    'talosctl must match the deployed Talos minor and patch release'
assert_contains tofu/main.tf 'bootstrap_endpoint_mode[[:space:]]*=[[:space:]]*"private_ip"' \
    'OpenTofu bootstrap must use the private node IP'
assert_contains tofu/main.tf 'kubeconfig_endpoint_mode[[:space:]]*=[[:space:]]*"private_ip"' \
    'kubeconfig must use the private API endpoint'
assert_contains tofu/main.tf 'enable_alias_ip[[:space:]]*=[[:space:]]*false' \
    'a single control plane must use its direct private IP instead of an HA VIP'
assert_contains tofu/main.tf 'talosconfig_endpoints_mode[[:space:]]*=[[:space:]]*"private_ip"' \
    'talosconfig must use private node IPs'
assert_contains tofu/main.tf 'hcloud_ccm_version[[:space:]]*=[[:space:]]*"1\.30\.1"' \
    'the Hetzner controller chart must be pinned against unrelated drift'
assert_contains tofu/main.tf 'kind[[:space:]]*=[[:space:]]*"WireguardConfig"' \
    'Talos must receive a native WireGuard configuration document'
assert_contains tofu/main.tf 'port[[:space:]]*=[[:space:]]*"51820"' \
    'Hetzner firewall must allow the WireGuard UDP port'
assert_contains tofu/main.tf 'protocol[[:space:]]*=[[:space:]]*"udp"' \
    'the WireGuard firewall rule must use UDP'
assert_not_contains tofu/variables.tf 'tailscale_auth_key|TF_VAR_tailscale_auth_key' \
    'the Talos host auth key must be removed from OpenTofu'
assert_not_contains tofu/main.tf 'firewall_(talos|kube)_api_source' \
    'public Talos and Kubernetes API firewall rules must be absent'
assert_not_contains tofu/talos.tf '"tailscale"' \
    'the Talos image must not contain the Tailscale extension'
assert_not_contains mise.toml 'tailnet_ipv4|tailscale ip -4 shire-control-plane-1' \
    'local client configs must not rewrite endpoints to a Tailnet IP'
assert_contains bootstrap/bootstrap.sh 'WIREGUARD_WORKSTATION_PRIVATE_KEY' \
    'the bootstrap ceremony must persist the workstation WireGuard key in SOPS'
assert_contains bootstrap/bootstrap.sh 'wg genkey' \
    'the bootstrap ceremony must generate WireGuard keys locally'
assert_not_contains bootstrap/bootstrap.sh 'Tailscale auth key|TF_VAR_tailscale_auth_key' \
    'the bootstrap ceremony must not request an expiring Talos host auth key'
assert_contains bootstrap/bootstrap.sh 'TAILSCALE_OAUTH_CLIENT_ID' \
    'the bootstrap ceremony must persist the Tailscale provider OAuth client ID'
assert_contains bootstrap/bootstrap.sh 'TAILSCALE_OAUTH_CLIENT_SECRET' \
    'the bootstrap ceremony must persist the Tailscale provider OAuth client secret'
assert_contains scripts/rebuild.sh 'module\.talos\.hcloud_primary_ip\.control_plane_ipv4' \
    'rebuild must allocate the stable public endpoint before private bootstrap'
assert_contains scripts/rebuild.sh 'wireguard:configure' \
    'rebuild must configure the workstation tunnel before the full apply'
assert_contains mise.toml '\[tasks\."wireguard:configure"\]' \
    'mise must expose the workstation WireGuard configuration task'
assert_contains mise.toml '\[tasks\."wireguard:recover"\]' \
    'mise must expose the WireGuard break-glass recovery task'

printf 'private management invariants passed\n'
