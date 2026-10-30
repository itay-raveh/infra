#!/usr/bin/env bats
load test_helper/common

setup() {
    local source_root
    source_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    setup_script_repo
    mkdir .github
    cp -R "$source_root/.github/rulesets" .github/
    setup_fakebin
    export CALLS="$BATS_TEST_TMPDIR/calls"
    cat > "$FAKEBIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
    'repo view '*) printf 'example/infra\n' ;;
    'api repos/example/infra/rulesets --paginate')
        printf '[{"id":1,"name":"main branch checks"},{"id":2,"name":"main branch security"},{"id":3,"name":"tag protection"},{"id":4,"name":"unrelated"}]\n' ;;
    'api repos/example/infra/environments/flux-image-automation/deployment-branch-policies --paginate')
        printf '{"branch_policies":%s}\n' "${POLICIES:-[]}" ;;
    *'--input -') cat >> "$CALLS" ;;
esac
SH
    chmod +x "$FAKEBIN/gh"
}

@test "GitHub configuration updates named rules without deleting unrelated protection" {
    run bash scripts/configure-github.sh
    [ "$status" -eq 0 ]
    for id in 1 2 3; do assert_file_contains "$CALLS" "--method PUT repos/example/infra/rulesets/$id"; done
    refute_file_contains "$CALLS" 'rulesets/4'
    refute_file_contains "$CALLS" DELETE
    assert_file_contains "$CALLS" '-f name=flux-image-automation -f type=branch'
    assert_file_contains "$CALLS" '"custom_branch_policies":true'
}

@test "GitHub configuration does not duplicate an existing environment branch rule" {
    run env POLICIES='[{"id":5,"name":"flux-image-automation","type":"branch"}]' bash scripts/configure-github.sh
    [ "$status" -eq 0 ]
    refute_file_contains "$CALLS" '--method POST'
}
