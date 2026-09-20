#!/usr/bin/env bats
load test_helper/common

setup() {
    setup_script_repo
    setup_fakebin
    mkdir -p bootstrap clusters/shire/flux-system
    touch bootstrap/cluster-age-key.sops.txt bootstrap/etcd-backup-age-key.sops.txt \
        clusters/shire/flux-system/flux-github-app.sops.yaml \
        clusters/shire/flux-system/github-web-flow.asc clusters/shire/flux-system/kustomization.yaml
    cat > clusters/shire/flux-system/gotk-sync.yaml <<'YAML'
kind: GitRepository
metadata:
  name: flux-system
spec:
  ref:
    branch: main
  url: https://github.com/example/infra.git
YAML
    export TF_VAR_ssh_public_key_path="$BATS_TEST_TMPDIR/signing.pub"
    touch "$TF_VAR_ssh_public_key_path"
    cat > "$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
case "$*" in
    'status --porcelain') ;;
    'branch --show-current') printf 'main\n' ;;
    'rev-parse --abbrev-ref @{upstream}') printf 'origin/main\n' ;;
    'remote get-url --push origin') printf '%s\n' "$TEST_ORIGIN" ;;
    *commit.gpgsign) printf 'true\n' ;;
    *gpg.format) printf 'ssh\n' ;;
    *user.signingkey) printf '%s\n' "$TF_VAR_ssh_public_key_path" ;;
    *) exit 1 ;;
esac
SH
    cat > "$FAKEBIN/gh" <<'SH'
#!/usr/bin/env bash
if [[ "$1 $2" == 'repo view' ]]; then
    case "$3" in
        git@github.com:example/infra.git|https://github.com/example/infra.git)
            printf 'https://github.com/example/infra\n' ;;
        *) printf 'https://github.com/example/other\n' ;;
    esac
elif [[ "$2" == 'repos/{owner}/{repo}/rulesets' ]]; then
    printf '1\n'
else
    printf 'true\n'
fi
SH
    cat > "$FAKEBIN/ykman" <<'SH'
#!/usr/bin/env bash
printf '123\n'
SH
    for command in mise sops tofu kubectl talosctl flux wg wg-quick sudo install systemctl ssh-keygen; do
        printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/$command"
    done
    chmod +x "$FAKEBIN/"*
}

@test "doctor accepts SSH and HTTPS remotes for the Flux repository" {
    for remote in git@github.com:example/infra.git https://github.com/example/infra.git; do
        run env TEST_ORIGIN="$remote" bash scripts/doctor.sh
        [ "$status" -eq 0 ]
        [[ "$output" == *'origin push targets the Flux repository'* ]]
    done
}

@test "doctor rejects a remote pointing at another repository" {
    run env TEST_ORIGIN=git@github.com:example/other.git bash scripts/doctor.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *'origin push targets a different repository'* ]]
}
