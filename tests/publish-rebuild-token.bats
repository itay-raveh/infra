#!/usr/bin/env bats
load test_helper/common

setup() {
    setup_script_repo
    setup_fakebin
    export CALLS="$BATS_TEST_TMPDIR/calls" PR_STATE=MERGED
    cat > "$FAKEBIN/git" <<'SH'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALLS"
case "$1" in
    diff) exit "${UNCHANGED:-1}" ;;
    commit) exit "${SIGNING_FAILURE:-0}" ;;
esac
SH
    cat > "$FAKEBIN/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS"
case "$1 $2" in
    'pr create') printf 'https://github.com/example/infra/pull/1\n' ;;
    'pr view') printf '%s\n' "$PR_STATE" ;;
esac
SH
    printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/sleep"
    chmod +x "$FAKEBIN/"*
}

@test "rebuild waits for a checked squash merge before returning to main" {
    run bash scripts/publish-rebuild-token.sh token.sops.yaml
    [ "$status" -eq 0 ]
    assert_file_contains "$CALLS" 'git push --set-upstream origin HEAD'
    assert_file_contains "$CALLS" 'gh pr merge https://github.com/example/infra/pull/1 --auto --squash'
    assert_file_contains "$CALLS" 'git switch main'
    assert_file_contains "$CALLS" 'git pull --ff-only'
}

@test "rebuild does nothing when the token is unchanged" {
    run env UNCHANGED=0 bash scripts/publish-rebuild-token.sh token.sops.yaml
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CALLS")" -eq 1 ]
}

@test "signing refusal stops rebuild before push" {
    run env SIGNING_FAILURE=1 bash scripts/publish-rebuild-token.sh token.sops.yaml
    [ "$status" -eq 1 ]
    refute_file_contains "$CALLS" 'git push'
    refute_file_contains "$CALLS" 'gh pr'
}

@test "unmerged rebuild PRs cannot proceed to Flux installation" {
    for state in CLOSED OPEN; do
        : > "$CALLS"
        run env PR_STATE="$state" bash scripts/publish-rebuild-token.sh token.sops.yaml
        [ "$status" -eq 1 ]
        refute_file_contains "$CALLS" 'git switch main'
    done
}
