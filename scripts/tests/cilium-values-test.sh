#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

readonly values=tofu/cilium-values.yaml

if [[ ! -f "$values" ]]; then
    printf 'FAIL: explicit Cilium values are required for the WireGuard device\n' >&2
    exit 1
fi

if ! grep -Eq 'cilium_values[[:space:]]*=[[:space:]]*\[file\("\$\{path\.module\}/cilium-values\.yaml"\)\]' tofu/main.tf; then
    printf 'FAIL: the Talos module must consume the reviewed Cilium values file\n' >&2
    exit 1
fi

actual=$(yq -o=json '.' "$values" | jq -S -c '.')
expected=$(jq -S -c -n '
    {
        operator: {
            replicas: 1,
            prometheus: {serviceMonitor: {enabled: false}}
        },
        ipam: {mode: "kubernetes"},
        routingMode: "native",
        ipv4NativeRoutingCIDR: "10.0.16.0/20",
        kubeProxyReplacement: true,
        bpf: {masquerade: false},
        loadBalancer: {acceleration: "best-effort"},
        encryption: {enabled: false, type: "wireguard"},
        securityContext: {
            capabilities: {
                ciliumAgent: [
                    "CHOWN",
                    "KILL",
                    "NET_ADMIN",
                    "NET_RAW",
                    "IPC_LOCK",
                    "SYS_ADMIN",
                    "SYS_RESOURCE",
                    "DAC_OVERRIDE",
                    "FOWNER",
                    "SETGID",
                    "SETUID"
                ],
                cleanCiliumState: ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
            }
        },
        cgroup: {autoMount: {enabled: false}, hostRoot: "/sys/fs/cgroup"},
        k8sServiceHost: "127.0.0.1",
        k8sServicePort: 7445,
        hubble: {enabled: false},
        prometheus: {
            serviceMonitor: {enabled: false, trustCRDsExist: false}
        }
    }
')

if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: explicit Cilium values diverge from the reviewed module defaults\n' >&2
    diff -u <(jq . <<< "$expected") <(jq . <<< "$actual") >&2 || true
    exit 1
fi

printf 'Cilium values preserve module defaults and use mixed-device XDP\n'
