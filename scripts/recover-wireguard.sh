#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "$0")/.."

set -a
eval "$(sops decrypt --output-type dotenv tofu/secrets.sops.yaml)"
set +a

: "${TF_VAR_wireguard_server_private_key:?missing TF_VAR_wireguard_server_private_key}"
: "${TF_VAR_wireguard_workstation_public_key:?missing TF_VAR_wireguard_workstation_public_key}"

public_ipv4=$(tofu -chdir=tofu output -raw public_ipv4)
# A fresh bootstrap has no private_ipv4 output until the first full apply.
private_ipv4=$(tofu -chdir=tofu output -raw private_ipv4 2>/dev/null || printf '10.0.1.101')
patch=$(mktemp)
talosconfig=$(mktemp)
diagnostic_capture=$(mktemp)
trap 'rm -f "$patch" "$talosconfig" "$diagnostic_capture"' EXIT

tofu -chdir=tofu output -raw talosconfig > "$talosconfig"
cat > "$patch" <<EOF
apiVersion: v1alpha1
kind: WireguardConfig
name: wg0
privateKey: $TF_VAR_wireguard_server_private_key
listenPort: 51820
addresses:
  - address: 10.200.0.1/24
peers:
  - publicKey: $TF_VAR_wireguard_workstation_public_key
    allowedIPs:
      - 10.200.0.250/32
EOF

printf 'Applying WireGuard in try mode through the temporary public Talos API rule.\n'
talosctl --talosconfig "$talosconfig" \
    --endpoints "$public_ipv4" --nodes "$public_ipv4" \
    patch machineconfig --patch "@$patch" --mode try --timeout 5m

mise run wireguard:configure

if [[ "${WIREGUARD_DIAGNOSTICS:-}" == 1 ]]; then
    printf '\nNode WireGuard link:\n'
    timeout 10 talosctl --talosconfig "$talosconfig" \
        --endpoints "$public_ipv4" --nodes "$public_ipv4" \
        get links wg0 || true

    printf '\nNode WireGuard address:\n'
    timeout 10 talosctl --talosconfig "$talosconfig" \
        --endpoints "$public_ipv4" --nodes "$public_ipv4" \
        get addresses | grep -E 'wg0|10\.200\.' || true

    printf '\nNode UDP 51820 listener:\n'
    timeout 10 talosctl --talosconfig "$talosconfig" \
        --endpoints "$public_ipv4" --nodes "$public_ipv4" \
        netstat --all --udp | grep -E '51820|Local Address' || true

    printf '\nCapturing server traffic while triggering a handshake:\n'
    timeout 10 talosctl --talosconfig "$talosconfig" \
        --endpoints "$public_ipv4" --nodes "$public_ipv4" \
        pcap -i eth0 > "$diagnostic_capture" 2>&1 &
    capture_pid=$!
    sleep 1
    ping -c 2 -W 2 10.200.0.1 >/dev/null 2>&1 || true
    wait "$capture_pid" || true
    if ! grep -E '51820|WireGuard' "$diagnostic_capture"; then
        printf 'No UDP 51820 packet appeared in the server capture.\n'
    fi
    printf '\n'
fi

printf 'Waiting for the private Talos endpoint before committing the patch.\n'
verify_attempts=${WIREGUARD_VERIFY_ATTEMPTS:-24}
verify_timeout=${WIREGUARD_VERIFY_TIMEOUT:-3}
verify_delay=${WIREGUARD_VERIFY_DELAY:-2}
for attempt in $(seq 1 "$verify_attempts"); do
    printf 'Private endpoint check %s/%s...\n' "$attempt" "$verify_attempts"
    if timeout "$verify_timeout" talosctl --talosconfig "$talosconfig" \
        --endpoints "$private_ipv4" --nodes "$private_ipv4" \
        version >/dev/null 2>&1; then
        talosctl --talosconfig "$talosconfig" \
            --endpoints "$private_ipv4" --nodes "$private_ipv4" \
            patch machineconfig --patch "@$patch" --mode no-reboot
        printf 'WireGuard is reachable and the Talos patch is persistent.\n'
        exit 0
    fi
    sleep "$verify_delay"
done

printf 'The private endpoint did not become reachable. Talos will roll back the try patch automatically.\n' >&2
exit 1
