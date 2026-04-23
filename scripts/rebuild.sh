#!/usr/bin/env bash
set -euo pipefail
git pull --rebase
set -a
eval "$(sops decrypt --output-type dotenv tofu/secrets.sops.yaml)"
set +a

echo "==> 1/5: creating Talos image"
tofu -chdir=tofu apply -auto-approve \
  -target=talos_image_factory_schematic.shire \
  -target=imager_image.shire

echo "==> 2/5: applying infrastructure"
tofu -chdir=tofu apply -auto-approve

echo "==> 3/5: syncing tunnel token + writing local configs"
mise run configs:refresh
target=clusters/shire/infrastructure/controllers/cloudflared-tunnel-token.sops.yaml
tofu -chdir=tofu output -raw tunnel_token \
  | bash scripts/refresh-sops-secret.sh "$target" cloudflared cloudflared-tunnel-token cf-tunnel-token
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

echo "==> 5/5: installing Flux and wiring to git via GitHub App"
flux install \
  --components-extra=image-reflector-controller,image-automation-controller
sops --decrypt clusters/shire/flux-system/flux-github-app.sops.yaml \
  | kubectl apply -f -
kubectl apply -f clusters/shire/flux-system/gotk-sync.yaml

echo "==> rebuild complete. watch with: flux get kustomizations --watch"
