#!/usr/bin/env bash
set -uo pipefail

failures=0
declare -A available=()

pass() {
    printf 'ok: %s\n' "$1"
}

fail() {
    printf 'error: %s\n' "$1" >&2
    failures=$((failures + 1))
}

for command in git gh mise sops ykman tofu kubectl flux yq wg wg-quick sudo install systemctl ssh-keygen; do
    if command -v "$command" >/dev/null 2>&1; then
        available[$command]=1
        pass "$command is available"
    else
        available[$command]=0
        fail "$command is not available"
    fi
done

flux_branch=
flux_repository=
if ((available[yq])) && [[ -f clusters/shire/flux-system/gotk-sync.yaml ]]; then
    flux_branch=$(yq -r '
        select(.kind == "GitRepository" and .metadata.name == "flux-system") |
        .spec.ref.branch
    ' clusters/shire/flux-system/gotk-sync.yaml)
    flux_repository=$(yq -r '
        select(.kind == "GitRepository" and .metadata.name == "flux-system") |
        .spec.url
    ' clusters/shire/flux-system/gotk-sync.yaml)
    if [[ -z "$flux_branch" || "$flux_branch" == "null" ]]; then
        fail "Flux source branch is not configured in gotk-sync.yaml"
        flux_branch=
    else
        pass "Flux reconciles branch $flux_branch"
    fi
fi

if ((available[git])); then
    if [[ -n $(git status --porcelain) ]]; then
        fail "git worktree is not clean"
    else
        pass "git worktree is clean"
    fi

    current_branch=$(git branch --show-current)
    upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
    if [[ -n "$flux_branch" && "$current_branch" != "$flux_branch" ]]; then
        fail "current branch $current_branch does not match Flux branch $flux_branch"
    elif [[ -n "$flux_branch" && "$upstream" != "origin/$flux_branch" ]]; then
        fail "git upstream $upstream does not match origin/$flux_branch"
    else
        pass "git branch and upstream match the Flux source"
    fi

    origin_push_url=$(git remote get-url --push origin 2>/dev/null || true)
    if [[ -n "$flux_repository" && "$origin_push_url" == "$flux_repository" ]]; then
        pass "origin push uses the Flux HTTPS repository"
    elif [[ -n "$flux_repository" ]]; then
        fail "origin push URL does not use the Flux HTTPS repository"
    fi

fi

if ((available[gh])); then
    github_access=$(gh api 'repos/{owner}/{repo}' \
        --jq '.permissions.admin and .permissions.push' 2>/dev/null || true)
    if [[ "$github_access" == "true" ]]; then
        pass "authenticated GitHub account has admin push access"

        ruleset_id=$(gh api 'repos/{owner}/{repo}/rulesets' \
            --jq '.[] | select(.name == "main branch checks" and .enforcement == "active") | .id' \
            2>/dev/null || true)
        bypass=false
        if [[ -n "$ruleset_id" ]]; then
            bypass=$(gh api "repos/{owner}/{repo}/rulesets/$ruleset_id" --jq '
                [.bypass_actors[]? |
                    select(.actor_type == "RepositoryRole" and
                           .actor_id == 5 and
                           (.bypass_mode == "always" or .bypass_mode == "exempt"))] |
                length > 0
            ' 2>/dev/null || true)
        fi

        if [[ "$bypass" == "true" ]]; then
            pass "main branch ruleset allows the admin rebuild push"
        else
            fail "main branch ruleset does not allow the admin rebuild push"
        fi
    else
        fail "authenticated GitHub account lacks admin push access"
    fi
fi

required_files=(
    tofu/secrets.sops.yaml
    bootstrap/cluster-age-key.sops.txt
    clusters/shire/flux-system/flux-github-app.sops.yaml
    clusters/shire/flux-system/gotk-sync.yaml
)

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        pass "$file exists"
    else
        fail "$file is missing"
    fi
done

ssh_public_key_path=${TF_VAR_ssh_public_key_path:-$HOME/.ssh/id_ed25519_sk.pub}
ssh_public_key_path=${ssh_public_key_path/#\~/$HOME}
if [[ -f "$ssh_public_key_path" ]]; then
    pass "$ssh_public_key_path exists"
else
    fail "$ssh_public_key_path is missing"
fi

if ((available[git] && available[ssh-keygen])); then
    signing_enabled=$(git config --bool --get commit.gpgsign 2>/dev/null || true)
    signing_format=$(git config --get gpg.format 2>/dev/null || true)
    signing_key=$(git config --path --get user.signingkey 2>/dev/null || true)

    if [[ "$signing_enabled" != "true" || "$signing_format" != "ssh" || -z "$signing_key" ]]; then
        fail "git SSH commit signing is not configured"
    elif [[ ! -f "$signing_key" ]]; then
        fail "configured SSH signing key is missing"
    elif printf 'infra rebuild signing probe' |
        ssh-keygen -Y sign -f "$signing_key" -n git >/dev/null 2>&1; then
        pass "configured SSH signing key can sign"
    else
        fail "configured SSH signing key cannot sign"
    fi
fi

if ((available[ykman])); then
    if ykman list --serials 2>/dev/null | read -r; then
        pass "YubiKey is connected"
    else
        fail "YubiKey is not connected"
    fi
fi

if ((available[sops])); then
    for file in \
        tofu/secrets.sops.yaml \
        bootstrap/cluster-age-key.sops.txt \
        clusters/shire/flux-system/flux-github-app.sops.yaml; do
        if sops decrypt "$file" >/dev/null 2>&1; then
            pass "can decrypt $file"
        else
            fail "cannot decrypt $file"
        fi
    done
fi

if ((available[sudo])); then
    if sudo -v; then
        pass "sudo authentication is available"
    else
        fail "sudo authentication failed"
    fi
fi

if ((available[sops] && available[tofu])) &&
    dotenv=$(sops decrypt --output-type dotenv tofu/secrets.sops.yaml 2>/dev/null); then
    if (
        set -a
        eval "$dotenv"
        set +a
        tofu -chdir=tofu init -input=false >/dev/null 2>&1 &&
            tofu -chdir=tofu state pull >/dev/null 2>&1
    ); then
        pass "OpenTofu state backend is accessible"
    else
        fail "cannot access the OpenTofu state backend"
    fi
elif ((available[sops] && available[tofu])); then
    fail "cannot load OpenTofu credentials from tofu/secrets.sops.yaml"
fi

if ((failures > 0)); then
    printf 'doctor: %d problems found\n' "$failures" >&2
    exit 1
fi

printf 'doctor: all rebuild prerequisites are ready\n'
