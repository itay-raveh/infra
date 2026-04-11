#!/usr/bin/env bash
# Two checks for the repo's SOPS hygiene:
#   1. Every file whose name claims to be encrypted (*.sops.yaml,
#      *.sops.json, *.sops.txt, *.sops) actually contains ENC[ markers.
#   2. Every k8s Secret manifest under clusters/ is either named *.sops.yaml
#      OR carries no plaintext stringData/data fields with non-empty values.
#      This catches the "I forgot to encrypt this" case at PR time.
#
# Exits non-zero on the first violation so the CI log points at the file.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

fail=0

# --- Check 1: SOPS-named files must be encrypted ---
mapfile -t sops_named < <(
  git ls-files \
    '*.sops.yaml' '*.sops.yml' '*.sops.json' \
    '*.sops.txt' '*.sops'
)

for f in "${sops_named[@]}"; do
  # The .sops.yaml config file at repo root is the one exception: it's
  # the rule file itself, not ciphertext. Skip exactly that path.
  if [ "$f" = ".sops.yaml" ]; then
    continue
  fi
  if ! grep -q 'ENC\[' "$f"; then
    echo "sops-sanity: not encrypted: $f" >&2
    fail=1
  fi
done

# --- Check 2: plaintext Secret bodies under clusters/ ---
# Anything that declares kind: Secret and isn't a *.sops.* filename
# must not contain stringData: or non-empty data: keys.
mapfile -t secret_manifests < <(
  git ls-files 'clusters/**/*.yaml' 'clusters/**/*.yml' 2>/dev/null \
    | grep -v '\.sops\.' || true
)

for f in "${secret_manifests[@]}"; do
  if grep -qE '^kind:[[:space:]]*Secret([[:space:]]|$)' "$f"; then
    echo "sops-sanity: plaintext Secret manifest (rename to .sops.yaml and encrypt): $f" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "sops-sanity: ok (${#sops_named[@]} encrypted files, ${#secret_manifests[@]} plaintext yamls scanned)"
