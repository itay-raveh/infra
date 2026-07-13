#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fakebin="$tmp/bin"
mkdir -p "$fakebin"

server_private=$(/usr/bin/wg genkey)
server_public=$(printf '%s' "$server_private" | /usr/bin/wg pubkey)
workstation_private=$(/usr/bin/wg genkey)
workstation_public=$(printf '%s' "$workstation_private" | /usr/bin/wg pubkey)

export TEST_SERVER_PRIVATE=$server_private
export TEST_WORKSTATION_PRIVATE=$workstation_private
export TEST_WORKSTATION_PUBLIC=$workstation_public
export TEST_CONFIG_CAPTURE="$tmp/shire.conf"

cat > "$fakebin/sops" <<'EOF'
#!/usr/bin/env bash
printf 'TF_VAR_wireguard_server_private_key=%q\n' "$TEST_SERVER_PRIVATE"
printf 'TF_VAR_wireguard_workstation_public_key=%q\n' "$TEST_WORKSTATION_PUBLIC"
printf 'WIREGUARD_WORKSTATION_PRIVATE_KEY=%q\n' "$TEST_WORKSTATION_PRIVATE"
EOF

cat > "$fakebin/tofu" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *'output -raw public_ipv4'* ]]; then
    printf '203.0.113.10'
    exit 0
fi
exit 1
EOF

cat > "$fakebin/wg" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "pubkey" ]]; then
    exec /usr/bin/wg pubkey
fi
exit 1
EOF

cat > "$fakebin/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "install" && "${2:-}" == "-d" ]]; then
    exit 0
fi
if [[ "${1:-}" == "install" && "${2:-}" == "-m" ]]; then
    install -m "$3" "$4" "$TEST_CONFIG_CAPTURE"
    exit 0
fi
exec "$@"
EOF

cat > "$fakebin/wg-quick" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$fakebin"/*

PATH="$fakebin:/usr/bin:/bin" bash "$repo_root/scripts/configure-wireguard.sh"

expected=$(cat <<EOF
[Interface]
PrivateKey = $workstation_private
Address = 10.200.0.250/24

[Peer]
PublicKey = $server_public
Endpoint = 203.0.113.10:51820
AllowedIPs = 10.200.0.0/24, 10.0.1.0/24
PersistentKeepalive = 25
EOF
)

actual=$(<"$TEST_CONFIG_CAPTURE")
if [[ "$actual" != "$expected" ]]; then
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2
    exit 1
fi

mode=$(stat -c '%a' "$TEST_CONFIG_CAPTURE")
if [[ "$mode" != "600" ]]; then
    printf 'FAIL: expected WireGuard config mode 600, got %s\n' "$mode" >&2
    exit 1
fi

printf 'configure-wireguard test passed\n'
