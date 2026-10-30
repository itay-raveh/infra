#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."

if [[ "${1:-}" != --decrypted ]]; then
    exec bash scripts/sops-exec.sh secrets/state.sops.yaml -- bash scripts/refresh-configs.sh --decrypted
fi

config_root=${INFRA_CONFIG_ROOT:-$HOME}
mkdir -p "$config_root/.kube" "$config_root/.talos"
kubeconfig='' talosconfig=''
trap 'rm -f "$kubeconfig" "$talosconfig"' EXIT
kubeconfig=$(mktemp "$config_root/.kube/config.XXXXXX")
talosconfig=$(mktemp "$config_root/.talos/config.XXXXXX")

tofu -chdir=tofu output -raw kubeconfig > "$kubeconfig"
tofu -chdir=tofu output -raw talosconfig > "$talosconfig"
private_ipv4=$(tofu -chdir=tofu output -raw private_ipv4)
test -s "$kubeconfig" && test -s "$talosconfig" && test -n "$private_ipv4"
kubectl --kubeconfig "$kubeconfig" config view --minify >/dev/null
talosctl --talosconfig "$talosconfig" config node "$private_ipv4"

mv -f "$kubeconfig" "$config_root/.kube/config"
mv -f "$talosconfig" "$config_root/.talos/config"
