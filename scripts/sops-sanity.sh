#!/usr/bin/env bash
# Two checks that together protect against committing plaintext secrets:
#   1. Every file named *.sops.* must actually be SOPS-encrypted (contain ENC[).
#   2. No plaintext k8s Secret (kind: Secret) in clusters/ outside *.sops.*.
# Called from .pre-commit-config.yaml and .github/workflows/validate.yaml.
set -euo pipefail

fail=0

if grep -rL "ENC\[" --include='*.sops.*' --exclude='.sops.yaml' . | grep .; then
  echo "^ files named *.sops.* but not SOPS-encrypted" >&2
  fail=1
fi

# Vendored cnpg plugin-barman-cloud manifest ships a kind:Secret
# containing only a base64 public image ref. Re-verify on version bumps.
if grep -rlE "^[[:space:]]*kind:[[:space:]]*Secret[[:space:]]*$" \
     --include='*.yaml' --include='*.yml' --exclude='*.sops.*' clusters/ \
   | grep -Fxv 'clusters/shire/infrastructure/controllers/barman-cloud-plugin/manifest.yaml' \
   | grep .; then
  echo "^ plaintext Secrets in clusters/ - rename to .sops.yaml and encrypt" >&2
  fail=1
fi

exit "$fail"
