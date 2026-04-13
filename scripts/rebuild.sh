#!/usr/bin/env bash
set -euo pipefail
set -a
eval "$(sops decrypt --output-type dotenv tofu/secrets.sops.yaml)"
set +a
KUBECONFIG="$(mktemp)"
export KUBECONFIG
trap 'rm -f "$KUBECONFIG"' EXIT

echo "==> 1/5: creating Talos image"
tofu -chdir=tofu apply -auto-approve \
  -target=talos_image_factory_schematic.shire \
  -target=imager_image.shire

echo "==> 2/5: applying infrastructure"
tofu -chdir=tofu apply -auto-approve

echo "==> 3/5: syncing tunnel token"
git pull --rebase
tofu -chdir=tofu output -raw kubeconfig > "$KUBECONFIG"
target=clusters/shire/infrastructure/controllers/cloudflared-tunnel-token.sops.yaml
token=$(tofu -chdir=tofu output -raw tunnel_token)
printf '%s' "$token" | kubectl create secret generic cloudflared-tunnel-token \
  --namespace=cloudflared \
  --from-file=cf-tunnel-token=/dev/stdin \
  --dry-run=client -o yaml > "$target"
sops --encrypt --in-place "$target"
git add "$target"
git commit -m "chore: tunnel token for fresh rebuild"
git push

echo "==> 4/5: seeding SOPS age key"
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
sops --decrypt bootstrap/cluster-age-key.sops.txt \
  | kubectl create secret generic sops-age \
      -n flux-system \
      --from-file=age.agekey=/dev/stdin \
      --dry-run=client -o yaml | kubectl apply -f -

echo "==> 5/5: bootstrapping Flux"
GITHUB_TOKEN="$(gh auth token)"
export GITHUB_TOKEN
flux bootstrap github \
  --owner=itay-raveh \
  --repository=infra \
  --path=clusters/shire \
  --personal \
  --branch=main

echo "==> rebuild complete. watch with: flux get kustomizations --watch"
