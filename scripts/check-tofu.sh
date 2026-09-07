#!/usr/bin/env bash
set -euo pipefail

# A fresh data directory avoids using the operator's initialized S3 backend.
validation_dir=$(mktemp -d)
trap 'rm -rf "$validation_dir"' EXIT
export TF_DATA_DIR="$validation_dir"
export AWS_ACCESS_KEY_ID=ci
export AWS_SECRET_ACCESS_KEY=ci
export TF_VAR_encryption_passphrase=ci

if [[ -n "${TF_PLUGIN_CACHE_DIR:-}" ]]; then
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
fi
tofu -chdir=tofu init -backend=false -lockfile=readonly
tofu -chdir=tofu validate
