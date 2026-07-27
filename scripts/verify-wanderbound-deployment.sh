#!/usr/bin/env bash
set -euo pipefail

release_version=${1:-}
namespace=wanderbound
public_url=https://wanderbound.raveh.dev

if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'usage: %s <x.y.z>\n' "$0" >&2
    exit 2
fi

diagnostics() {
    kubectl --namespace "$namespace" get helmrelease wanderbound || true
    kubectl --namespace "$namespace" get pods -o wide || true
    kubectl --namespace "$namespace" describe deployment wanderbound || true
}
trap diagnostics ERR

flux reconcile source oci wanderbound-chart --namespace "$namespace"
flux reconcile helmrelease wanderbound --namespace "$namespace"
kubectl --namespace "$namespace" wait \
    --for=condition=ready helmrelease/wanderbound --timeout=10m
kubectl --namespace "$namespace" rollout status deployment/wanderbound --timeout=10m

deployed_version=$(kubectl --namespace "$namespace" get helmrelease wanderbound \
    -o 'jsonpath={.status.history[0].appVersion}')
if [[ "$deployed_version" != "$release_version" ]]; then
    printf 'expected app version %s, found %s\n' "$release_version" "$deployed_version" >&2
    exit 1
fi

expected_image="ghcr.io/itay-raveh/wanderbound:$release_version"
deployed_image=$(kubectl --namespace "$namespace" get deployment wanderbound \
    -o 'jsonpath={.spec.template.spec.containers[?(@.name=="wanderbound")].image}')
if [[ "$deployed_image" != "$expected_image" ]]; then
    printf 'expected image %s, found %s\n' "$expected_image" "$deployed_image" >&2
    exit 1
fi

init_containers=$(kubectl --namespace "$namespace" get deployment wanderbound \
    -o 'jsonpath={.spec.template.spec.initContainers[*].name}')
if [[ " $init_containers " == *' migrations '* ]]; then
    printf 'removed migrations init container is still present\n' >&2
    exit 1
fi

curl --fail --silent --show-error "$public_url" >/dev/null
curl --fail --silent --show-error "$public_url/api/v1/health" \
    | jq -e '.db == true and .disk == true and .playwright == true' >/dev/null

trap - ERR
printf 'Wanderbound %s deployment verified.\n' "$release_version"
