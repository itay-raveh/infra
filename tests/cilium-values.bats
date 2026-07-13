#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    VALUES=tofu/cilium-values.yaml
}

@test "passes the reviewed Cilium values file to the Talos module" {
    run grep -En 'cilium_values[[:space:]]*=[[:space:]]*\[file\(.*cilium-values\.yaml.*\)\]' tofu/main.tf

    [ "$status" -eq 0 ]
}

@test "keeps mixed-device acceleration and critical module defaults" {
    run yq -e '.loadBalancer.acceleration == "best-effort" and .routingMode == "native" and .ipv4NativeRoutingCIDR == "10.0.16.0/20" and .kubeProxyReplacement == true and .bpf.masquerade == false and .cgroup.autoMount.enabled == false and .cgroup.hostRoot == "/sys/fs/cgroup" and .k8sServiceHost == "127.0.0.1" and .k8sServicePort == 7445 and .hubble.enabled == false and .operator.replicas == 1' "$VALUES"

    [ "$status" -eq 0 ]
}

@test "retains the required Cilium capabilities" {
    agent=$(yq -o=json '.securityContext.capabilities.ciliumAgent' "$VALUES")
    cleaner=$(yq -o=json '.securityContext.capabilities.cleanCiliumState' "$VALUES")

    run jq -e '. == ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]' <<<"$agent"
    [ "$status" -eq 0 ]
    run jq -e '. == ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]' <<<"$cleaner"
    [ "$status" -eq 0 ]
}
