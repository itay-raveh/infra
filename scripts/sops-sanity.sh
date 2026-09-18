#!/usr/bin/env bash
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
