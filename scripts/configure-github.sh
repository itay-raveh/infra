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

environment="repos/$repo/environments/flux-image-automation"
printf '%s\n' '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' |
    gh api --method PUT "$environment" --input - >/dev/null
policy=$(gh api "$environment/deployment-branch-policies" --paginate |
    jq -r '.branch_policies[] | select(.name == "flux-image-automation" and .type == "branch") | .id')
if [[ -z "$policy" ]]; then
    gh api --method POST "$environment/deployment-branch-policies" \
        -f name=flux-image-automation -f type=branch >/dev/null
fi
