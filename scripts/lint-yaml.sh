#!/usr/bin/env bash
set -euo pipefail

ordinary_files=()
flux_file=clusters/shire/flux-system/gotk-components.yaml
lint_flux=false
for file in "$@"; do
  if [[ "$file" == "$flux_file" ]]; then
    lint_flux=true
  else
    ordinary_files+=("$file")
  fi
done

status=0
if ((${#ordinary_files[@]})); then
  yamllint "${ordinary_files[@]}" || status=1
fi
if "$lint_flux"; then
  # Flux generates unindented sequences. Keep every other YAML rule active.
  yamllint -d '{extends: .yamllint, rules: {indentation: {indent-sequences: whatever}}}' "$flux_file" || status=1
fi
exit "$status"
