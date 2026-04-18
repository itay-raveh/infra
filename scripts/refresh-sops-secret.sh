#!/usr/bin/env bash
# Render a k8s Secret from stdin and SOPS-encrypt it in place.
# Usage: <token-producer> | refresh-sops-secret.sh <target> <namespace> <name> <key>
set -euo pipefail

target=$1
ns=$2
name=$3
key=$4

kubectl create secret generic "$name" \
  --namespace="$ns" \
  --from-file="$key=/dev/stdin" \
  --dry-run=client -o yaml > "$target"
sops --encrypt --in-place "$target"
echo "wrote $target - review, commit, and push when ready" >&2
