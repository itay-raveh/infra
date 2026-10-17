#!/usr/bin/env bash
set -euo pipefail

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
for file in .github/rulesets/*.json; do
    name=$(jq -r .name "$file")
    id=$(gh api "repos/$repo/rulesets" --paginate | jq -r --arg name "$name" '.[] | select(.name == $name) | .id')
    if [[ -n "$id" ]]; then
        gh api --method PUT "repos/$repo/rulesets/$id" --input "$file" >/dev/null
    else
        gh api --method POST "repos/$repo/rulesets" --input "$file" >/dev/null
    fi
done
