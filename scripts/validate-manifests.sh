#!/usr/bin/env bash
set -euo pipefail

rendered=$(mktemp -d)
trap 'rm -rf "$rendered"' EXIT

kubeconform_args=(
    -strict
    -summary
    -kubernetes-version 1.35.2
    -schema-location default
    -schema-location 'https://k8s-schemas.home-operations.com/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
)

render_flux_kustomization() {
    local name=$1
    local path=$2
    local definition=$3
    local output="$rendered/$name.yaml"

    flux build kustomization "$name" \
        --path "$path" \
        --kustomization-file "$definition" \
        --dry-run > "$output"
    kubeconform "${kubeconform_args[@]}" "$output"
}

render_flux_kustomization \
    flux-system \
    clusters/shire \
    clusters/shire/flux-system/gotk-sync.yaml

render_flux_kustomization \
    infrastructure \
    clusters/shire/infrastructure/controllers \
    clusters/shire/infrastructure.yaml

render_flux_kustomization \
    infrastructure-configs \
    clusters/shire/infrastructure/configs \
    clusters/shire/infrastructure-configs.yaml

render_flux_kustomization \
    apps \
    clusters/shire/apps \
    clusters/shire/apps.yaml

chart=clusters/shire/apps/wanderbound/app-chart.yaml
chart_url=$(yq -r 'select(.kind == "OCIRepository") | .spec.url' "$chart")
chart_version=$(yq -r 'select(.kind == "OCIRepository") | .spec.ref.tag' "$chart")
helm template wanderbound "$chart_url" \
    --version "$chart_version" \
    --namespace wanderbound \
    --values <(yq 'select(.kind == "HelmRelease") | .spec.values' "$chart") \
    --output-dir "$rendered/chart" >/dev/null
kubeconform "${kubeconform_args[@]}" "$rendered/chart"
