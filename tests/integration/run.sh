#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(git rev-parse --show-toplevel)"
test_dir=$(mktemp -d)
cluster="infra-test-$(basename "$test_dir" | tr '[:upper:]' '[:lower:]' | tr -d '.')"
export KUBECONFIG="$test_dir/kubeconfig"
export MC_CONFIG_DIR="$test_dir/mc"
forward_pid=
cleanup() {
  local status=$?
  if (( status != 0 )); then
    kubectl get pods -A || true
    kubectl get events -A --sort-by=.lastTimestamp | tail -40 || true
    flux get all -A || true
  fi
  [[ -z "$forward_pid" ]] || kill "$forward_pid" 2>/dev/null || true
  kind delete cluster --name "$cluster" || status=1
  rm -rf "$test_dir" || status=1
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
kind create cluster --name "$cluster" --config tests/integration/kind.yaml --wait 120s
[[ $(kubectl config current-context) == "kind-$cluster" ]]
flux install --components=source-controller,kustomize-controller,helm-controller
kubectl create namespace fixture
kubectl -n fixture run minio \
  --image=quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e \
  --env=MINIO_ROOT_USER=fixture-access --env=MINIO_ROOT_PASSWORD=fixture-secret \
  -- server /data
kubectl -n fixture expose pod minio --port=9000
kubectl -n fixture wait pod/minio --for=condition=Ready --timeout=180s
kubectl -n fixture port-forward svc/minio :9000 > "$test_dir/forward.log" 2>&1 &
forward_pid=$!
for ((attempt=0; attempt<30; attempt++)); do
  port=$(sed -n 's/Forwarding from 127.0.0.1:\([0-9]*\).*/\1/p' "$test_dir/forward.log")
  [[ -z "$port" ]] || break
  sleep 1
done
mc alias set fixture "http://127.0.0.1:${port:?MinIO port forward failed}" fixture-access fixture-secret
mc mb fixture/manifests fixture/backups

mkdir "$test_dir/manifests"
age-keygen -o "$test_dir/age.key" 2> /dev/null
age-keygen -o "$test_dir/wrong-age.key" 2> /dev/null
kubectl -n flux-system create secret generic sops-age --from-file=age.agekey="$test_dir/wrong-age.key"
kubectl -n fixture create secret generic recovered-secret --from-literal=message=decrypted-by-flux \
  --dry-run=client -o yaml > "$test_dir/secret.yaml"
sops --config /dev/null encrypt --age "$(age-keygen -y "$test_dir/age.key")" --encrypted-regex '^(data|stringData)$' \
  "$test_dir/secret.yaml" > "$test_dir/manifests/secret.sops.yaml"
mc cp "$test_dir/manifests/secret.sops.yaml" fixture/manifests/
flux create source bucket fixture --bucket-name=manifests --endpoint=minio.fixture.svc.cluster.local:9000 \
  --insecure --access-key=fixture-access --secret-key=fixture-secret --interval=1m
flux create kustomization fixture --source=Bucket/fixture --prune --wait \
  --decryption-provider=sops --decryption-secret=sops-age --export | kubectl apply -f -
kubectl -n flux-system wait kustomization/fixture \
  --for=jsonpath='{.status.conditions[?(@.type=="Ready")].reason}'=BuildFailed --timeout=120s
kubectl -n flux-system get kustomization fixture -o json | \
  jq -e '.status.conditions[] | select(.type == "Ready") | .message | contains("decryption failed")'
missing=$(kubectl -n fixture get secret recovered-secret --ignore-not-found -o name)
[[ -z "$missing" ]]
printf 'Flux rejected the wrong age key without applying the Secret.\n'
kubectl -n flux-system create secret generic sops-age --from-file=age.agekey="$test_dir/age.key" \
  --dry-run=client -o yaml | kubectl apply -f -
flux reconcile kustomization fixture --with-source
[[ $(kubectl -n fixture get secret recovered-secret -o jsonpath='{.data.message}' | base64 -d) == decrypted-by-flux ]]
printf 'Flux/SOPS recovery passed.\n'

kubectl apply -f clusters/shire/infrastructure/controllers/cert-manager.yaml
kubectl apply -f clusters/shire/infrastructure/controllers/cnpg.yaml
kubectl -n flux-system wait helmrelease/cert-manager helmrelease/cnpg --for=condition=Ready --timeout=300s
kubectl apply -f clusters/shire/infrastructure/controllers/barman-cloud-plugin/manifest.yaml
kubectl -n cnpg-system rollout status deployment/barman-cloud --timeout=180s
bash tests/integration/recovery.sh
printf 'All integration checks passed.\n'
