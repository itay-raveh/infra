#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
export SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}

mapfile -d '' files < <(
  find clusters tofu bootstrap -type f \
    \( -name '*.sops.yaml' -o -name '*.sops.json' -o -name '*.sops.txt' \) \
    -print0 | sort -z
)

for file in "${files[@]}"; do
  echo "Rewrapping $file"
  mise exec -- sops updatekeys --yes "$file"
done
