#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/.."

set -a
eval "$(sops decrypt --output-type dotenv tofu/secrets.sops.yaml)"
set +a

: "${TF_VAR_wireguard_server_private_key:?missing TF_VAR_wireguard_server_private_key}"
: "${TF_VAR_wireguard_workstation_public_key:?missing TF_VAR_wireguard_workstation_public_key}"
: "${WIREGUARD_WORKSTATION_PRIVATE_KEY:?missing WIREGUARD_WORKSTATION_PRIVATE_KEY}"

server_public_key=$(printf '%s' "$TF_VAR_wireguard_server_private_key" | wg pubkey)
public_ipv4=$(tofu -chdir=tofu output -raw public_ipv4)

config=$(mktemp)
trap 'rm -f "$config"' EXIT

cat > "$config" <<EOF
[Interface]
PrivateKey = $WIREGUARD_WORKSTATION_PRIVATE_KEY
Address = 10.200.0.250/24

[Peer]
PublicKey = $server_public_key
Endpoint = $public_ipv4:51820
AllowedIPs = 10.200.0.0/24, 10.0.1.0/24
PersistentKeepalive = 25
EOF

sudo install -d -m 700 /etc/wireguard
sudo install -m 600 "$config" /etc/wireguard/shire.conf

if sudo wg show shire >/dev/null 2>&1; then
    sudo wg-quick down shire
fi
sudo wg-quick up shire

printf 'WireGuard interface shire is active.\n'
