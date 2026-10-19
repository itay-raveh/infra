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
policies=$(gh api "$environment/deployment-branch-policies" --paginate)
for branch in flux-image-automation main; do
    if ! jq -e --arg branch "$branch" '.branch_policies | any(.name == $branch and .type == "branch")' <<< "$policies" >/dev/null; then
        gh api --method POST "$environment/deployment-branch-policies" \
            -f name="$branch" -f type=branch >/dev/null
    fi
done
