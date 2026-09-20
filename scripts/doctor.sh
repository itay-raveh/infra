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

for command in git gh mise sops ykman tofu kubectl talosctl flux jq yq wg wg-quick sudo install systemctl ssh-keygen; do
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
    if ((available[gh])) && [[ -n "$flux_repository" ]]; then
        origin_repository=$(gh repo view "$origin_push_url" --json url --jq .url 2>/dev/null || true)
        if [[ -n "$origin_push_url" && "$origin_repository" == "${flux_repository%.git}" ]]; then
            pass "origin push targets the Flux repository"
        else
            fail "origin push targets a different repository from Flux"
        fi
    fi

fi

if ((available[gh])); then
    github_access=$(gh api 'repos/{owner}/{repo}' --jq '.permissions.push' 2>/dev/null || true)
    if [[ "$github_access" == "true" ]]; then
        pass "authenticated GitHub account can push branches and open rebuild PRs"
    else
        fail "authenticated GitHub account lacks repository push access"
    fi
fi

required_files=(
    secrets/state.sops.yaml
    secrets/tofu.sops.yaml
    secrets/wireguard.sops.yaml
    secrets/workstation.sops.yaml
    bootstrap/cluster-age-key.sops.txt
    bootstrap/etcd-backup-age-key.sops.txt
    clusters/shire/flux-system/flux-github-app.sops.yaml
    clusters/shire/flux-system/gotk-sync.yaml
    clusters/shire/flux-system/github-web-flow.asc
    clusters/shire/flux-system/kustomization.yaml
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
        secrets/tofu.sops.yaml \
        secrets/wireguard.sops.yaml \
        secrets/workstation.sops.yaml \
        bootstrap/cluster-age-key.sops.txt \
        bootstrap/etcd-backup-age-key.sops.txt \
        clusters/shire/flux-system/flux-github-app.sops.yaml; do
        printf 'check: decrypting %s\n' "$file"
        if sops decrypt "$file" >/dev/null; then
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

if ((available[sops] && available[tofu])); then
    if bash scripts/sops-exec.sh secrets/state.sops.yaml -- sh -ec '
        printf "check: initializing OpenTofu backend\n"
        tofu -chdir=tofu init -input=false >/dev/null
        printf "check: reading OpenTofu state\n"
        tofu -chdir=tofu state pull >/dev/null
    '; then
        pass "OpenTofu state backend is accessible"
    else
        fail "cannot access the OpenTofu state backend"
    fi
fi

if ((failures > 0)); then
    printf 'doctor: %d problems found\n' "$failures" >&2
    exit 1
fi

printf 'doctor: all rebuild prerequisites are ready\n'
