#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fakebin="$tmp/bin"
mkdir -p "$fakebin"

server_private=$(wg genkey)
workstation_private=$(wg genkey)
workstation_public=$(printf '%s' "$workstation_private" | wg pubkey)

cat > "$fakebin/sops" <<EOF
#!/usr/bin/env bash
printf 'TF_VAR_wireguard_server_private_key=%q\n' '$server_private'
printf 'TF_VAR_wireguard_workstation_public_key=%q\n' '$workstation_public'
EOF

cat > "$fakebin/tofu" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
    public_ipv4) printf '203.0.113.10' ;;
    private_ipv4) exit 1 ;;
    talosconfig) printf 'context: test\n' ;;
    *) exit 1 ;;
esac
EOF

cat > "$fakebin/mise" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$tmp/mise.log'
EOF

cat > "$fakebin/talosctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$tmp/talosctl.log'
if [[ "\$*" == *' version'* && "\${TEST_TALOS_VERSION_MODE:-}" == hang ]]; then
    sleep 10
fi
if [[ "\$*" == *' patch machineconfig '* ]]; then
    patch_arg=\$(printf '%s\n' "\$*" | sed -n 's/.*--patch @\([^ ]*\).*/\1/p')
    cp "\$patch_arg" '$tmp/last-patch.yaml'
fi
EOF

chmod +x "$fakebin"/*

PATH="$fakebin:/usr/bin:/bin" bash "$repo_root/scripts/recover-wireguard.sh"

grep -Fq -- '--endpoints 203.0.113.10 --nodes 203.0.113.10 patch machineconfig' "$tmp/talosctl.log"
grep -Fq -- '--mode try --timeout 5m' "$tmp/talosctl.log"
grep -Fq -- '--endpoints 10.0.1.101 --nodes 10.0.1.101 version' "$tmp/talosctl.log"
grep -Fq -- '--endpoints 10.0.1.101 --nodes 10.0.1.101 patch machineconfig' "$tmp/talosctl.log"
grep -Fq -- '--mode no-reboot' "$tmp/talosctl.log"
grep -Fq 'run wireguard:configure' "$tmp/mise.log"
grep -Fq 'kind: WireguardConfig' "$tmp/last-patch.yaml"
grep -Fq "privateKey: $server_private" "$tmp/last-patch.yaml"
grep -Fq "publicKey: $workstation_public" "$tmp/last-patch.yaml"

started=$SECONDS
if TEST_TALOS_VERSION_MODE=hang \
    WIREGUARD_VERIFY_ATTEMPTS=1 \
    WIREGUARD_VERIFY_TIMEOUT=1 \
    WIREGUARD_VERIFY_DELAY=0 \
    PATH="$fakebin:/usr/bin:/bin" bash "$repo_root/scripts/recover-wireguard.sh"; then
    printf 'FAIL: an unreachable private endpoint must fail recovery\n' >&2
    exit 1
fi
if (( SECONDS - started > 3 )); then
    printf 'FAIL: an unreachable private endpoint probe exceeded its timeout\n' >&2
    exit 1
fi

printf 'recover-wireguard test passed\n'
