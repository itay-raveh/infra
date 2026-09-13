#!/usr/bin/env bash
set -euo pipefail

validation_dir=$(mktemp -d)
trap 'rm -rf "$validation_dir"' EXIT
kubernetes_version=$(sed -n 's/.*kubernetes_version *= "v\([^"]*\)"/\1/p' tofu/locals.tf)
talos_version=$(sed -n 's/.*talos_version *= "\([^"]*\)"/\1/p' tofu/locals.tf)
: "${kubernetes_version:?Missing Kubernetes version}" "${talos_version:?Missing Talos version}"

flate build all --path clusters/shire --kube-version "$kubernetes_version" \
  --skip-secrets=false --skip-crds=false --no-progress -o yaml > "$validation_dir/rendered.yaml"
kubectl kustomize clusters/shire > "$validation_dir/root.yaml"
flux install --export --components-extra=image-reflector-controller,image-automation-controller > "$validation_dir/flux.yaml"
# Talos installs this CRD itself, outside the Flux resource graph.
curl --fail --silent --show-error --retry 3 --max-time 60 \
  "https://raw.githubusercontent.com/siderolabs/talos/$talos_version/internal/app/machined/pkg/controllers/k8s/internal/k8stemplates/testdata/talos-service-account-crd.yaml" \
  -o "$validation_dir/talos.yaml"
flux-schema extract k8s --version "$kubernetes_version" -d "$validation_dir/schemas" > /dev/null
flux-schema extract crd "$validation_dir/rendered.yaml" "$validation_dir/flux.yaml" \
  "$validation_dir/talos.yaml" -d "$validation_dir/schemas" > /dev/null
flux-schema validate "$validation_dir/rendered.yaml" "$validation_dir/root.yaml" \
  --schema-location "$validation_dir/schemas" --skip-json-path v1/Secret:/sops
