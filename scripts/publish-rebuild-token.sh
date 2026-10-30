#!/usr/bin/env bash
set -euo pipefail

target=${1:?Expected the encrypted tunnel-token path}
if git diff --quiet -- "$target"; then
    exit 0
fi

git switch -c "rebuild/tunnel-token-$(date -u +%Y%m%dT%H%M%SZ)"
git add -- "$target"
git commit -m "chore: refresh tunnel token for rebuild"
git push --set-upstream origin HEAD
pr=$(gh pr create --base main --title "chore: refresh tunnel token for rebuild" \
    --body "Update the encrypted tunnel token for the rebuilt cluster.")
gh pr merge "$pr" --auto --squash
printf 'Waiting for CI and merge: %s\n' "$pr"

for ((attempt = 0; attempt < 60; attempt++)); do
    case $(gh pr view "$pr" --json state --jq .state) in
        MERGED)
            git switch main
            git pull --ff-only
            exit 0
            ;;
        CLOSED)
            printf 'Rebuild PR was closed without merging: %s\n' "$pr" >&2
            exit 1
            ;;
    esac
    sleep 30
done
printf 'Rebuild PR has not merged: %s\nMerge it before installing Flux.\n' "$pr" >&2
exit 1
