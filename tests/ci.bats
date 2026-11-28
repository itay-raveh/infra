#!/usr/bin/env bats
load test_helper/common

setup() {
    setup_repo
    yq -r '.jobs.checks.steps[0].run' .github/workflows/ci.yaml > "$BATS_TEST_TMPDIR/gate.sh"
    jq -n '{
        changes: {result: "success", outputs: {shell: "true", tofu: "true", manifests: "true", recovery: "true"}},
        lint: {result: "success"}, shell: {result: "success"}, tofu: {result: "success"},
        manifests: {result: "success"}, recovery: {result: "success"}
    }' > "$BATS_TEST_TMPDIR/passing.json"
}

run_gate() {
    run env NEEDS="$1" bash "$BATS_TEST_TMPDIR/gate.sh"
}

@test "CI gate runs after and accounts for every other job" {
    run yq -o=json '.jobs' .github/workflows/ci.yaml
    [ "$status" -eq 0 ]
    jq -e '(.checks.needs | sort) == (del(.checks) | keys) and .checks.if == "always()"' <<< "$output"
}

@test "CI gate accepts successful selected jobs and deliberately skipped jobs" {
    local needs
    needs=$(cat "$BATS_TEST_TMPDIR/passing.json")
    run_gate "$needs"
    [ "$status" -eq 0 ]
    for job in shell tofu manifests recovery; do
        needs=$(jq --arg job "$job" '.changes.outputs[$job] = "false" | .[$job].result = "skipped"' <<< "$needs")
        run_gate "$needs"
        [ "$status" -eq 0 ]
    done
}

@test "CI gate rejects failure cancellation or skipping of a required job" {
    local needs
    for job in changes lint shell tofu manifests recovery; do
        for result in failure cancelled skipped; do
            needs=$(jq --arg job "$job" --arg result "$result" '.[$job].result = $result' "$BATS_TEST_TMPDIR/passing.json")
            run_gate "$needs"
            [ "$status" -ne 0 ]
        done
    done
}

@test "CI gate rejects missing or invalid path selection and missing results" {
    local needs
    for change in 'del(.changes.outputs)' '.changes.outputs = {}' \
        '.changes.outputs.tofu = ""' '.changes.outputs.tofu = "invalid"' \
        'del(.tofu)' '.tofu.result = null'; do
        needs=$(jq "$change" "$BATS_TEST_TMPDIR/passing.json")
        run_gate "$needs"
        [ "$status" -ne 0 ]
    done
}

setup_image_pr() {
    setup_fakebin
    yq -r '.jobs.pr.steps[-1].run' .github/workflows/flux-image-auto-pr.yaml > "$BATS_TEST_TMPDIR/image-pr.sh"
    export GH_REPO=example/infra GITHUB_REF=refs/heads/main GITHUB_SHA=head
    export CALLS="$BATS_TEST_TMPDIR/calls" FIXTURES="$BATS_TEST_TMPDIR"
    printf '[{"number":42}]\n' > "$FIXTURES/prs.json"
    cat > "$FIXTURES/pr.json" <<'JSON'
{"state":"open","draft":false,"user":{"login":"infra-flux[bot]"},"auto_merge":{},
 "head":{"ref":"flux-image-automation","sha":"head","repo":{"full_name":"example/infra"}},"base":{"ref":"main"}}
JSON
    cat > "$FIXTURES/commit.json" <<'JSON'
{"parents":[{}],"author":{"name":"flux","email":"flux@raveh.dev"},"message":"deploy: update wanderbound release"}
JSON
    jq -n '{behind_by:1,files:[
      {filename:"clusters/shire/apps/wanderbound/app-chart.yaml",status:"modified",additions:1,deletions:1,
       patch:"@@ -10 +10 @@\n-    tag: 1.14.3 # {\"$imagepolicy\": \"flux-system:wanderbound:tag\"}\n+    tag: 1.15.0 # {\"$imagepolicy\": \"flux-system:wanderbound:tag\"}"},
      {filename:"clusters/shire/apps/quizmon/release/app-chart.yaml",status:"modified",additions:1,deletions:1,
       patch:("@@ -44 +44 @@\n-      digest: sha256:" + ("1" * 64) + " # {\"$imagepolicy\": \"flux-system:quizmon:digest\"}\n+      digest: sha256:" + ("2" * 64) + " # {\"$imagepolicy\": \"flux-system:quizmon:digest\"}")}
    ]}' > "$FIXTURES/comparison.json"
    cat > "$FAKEBIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
    'pr list '*) jq -r "${@: -1}" "$FIXTURES/prs.json" ;;
    'api repos/example/infra/git/ref/heads/flux-image-automation --jq .object.sha') echo head ;;
    'api repos/example/infra/git/ref/heads/main --jq .object.sha') echo main ;;
    'api repos/example/infra/git/commits/head') cat "$FIXTURES/commit.json" ;;
    'api repos/example/infra/compare/main...head') cat "$FIXTURES/comparison.json" ;;
    'api repos/example/infra/pulls/42') cat "$FIXTURES/pr.json" ;;
    'api repos/example/infra/pulls/42/update-branch '*) exit "${UPDATE_STATUS:-0}" ;;
    'pr create '*) echo https://github.com/example/infra/pull/42 ;;
    'pr merge '*) exit "${MERGE_STATUS:-0}" ;;
    *) exit 1 ;;
esac
SH
    chmod +x "$FAKEBIN/gh"
}

@test "Main advance refreshes the validated image PR with an expected head and waits for its push" {
    setup_image_pr
    run bash "$FIXTURES/image-pr.sh"
    [ "$status" -eq 0 ]
    assert_file_contains "$CALLS" 'pr merge 42 --disable-auto'
    assert_file_contains "$CALLS" 'pulls/42/update-branch --method PUT -f expected_head_sha=head'
    refute_file_contains "$CALLS" '--auto'
    refute_file_contains "$CALLS" 'pr create'
}

@test "Current image PR enables ordinary squash auto-merge only for the validated head" {
    setup_image_pr
    jq '.behind_by = 0' "$FIXTURES/comparison.json" > "$FIXTURES/current.json"
    mv "$FIXTURES/current.json" "$FIXTURES/comparison.json"
    run bash "$FIXTURES/image-pr.sh"
    [ "$status" -eq 0 ]
    assert_file_contains "$CALLS" 'pr merge 42 --auto --squash --match-head-commit head'
    refute_file_contains "$CALLS" 'update-branch'
}

@test "Main push with no image PR never creates one" {
    setup_image_pr
    echo '[]' > "$FIXTURES/prs.json"
    run bash "$FIXTURES/image-pr.sh"
    [ "$status" -eq 0 ]
    refute_file_contains "$CALLS" 'pr create'
    refute_file_contains "$CALLS" 'api '
}

@test "Only a current Flux image commit creates a PR" {
    setup_image_pr
    export GITHUB_REF=refs/heads/flux-image-automation
    echo '[]' > "$FIXTURES/prs.json"
    run bash "$FIXTURES/image-pr.sh"
    [ "$status" -eq 0 ]
    assert_file_contains "$CALLS" 'pr create --head flux-image-automation --base main'
    cp "$FIXTURES/commit.json" "$FIXTURES/flux-commit.json"
    for change in '.parents += [{}]' '.author.name = "someone"' '.message = "other change"'; do
        jq "$change" "$FIXTURES/flux-commit.json" > "$FIXTURES/commit.json"
        : > "$CALLS"
        run bash "$FIXTURES/image-pr.sh"
        [ "$status" -eq 0 ]
        refute_file_contains "$CALLS" 'pr create'
    done
    : > "$CALLS"
    run env GITHUB_SHA=old-head bash "$FIXTURES/image-pr.sh"
    [ "$status" -eq 0 ]
    refute_file_contains "$CALLS" 'pr create'
}

@test "Image PR rejects unexpected files, truncated patches and changes outside the exact setters" {
    setup_image_pr
    cp "$FIXTURES/comparison.json" "$FIXTURES/valid.json"
    local change
    for change in '.files = []' '.files += [.files[0]]' '.files[0].filename = ".github/workflows/ci.yaml"' \
        '.files[0].patch = null' '.files[0].status = "added"' '.files[0].additions = 2' \
        '.files[0].patch |= sub("1.15.0"; "latest")' '.files[1].patch |= sub("sha256:"; "sha512:")' \
        '.files[0].patch |= sub("\\+    tag"; "+  tag")' '.files[0].patch += "\n+    replicas: 0"' \
        '.files[0].patch |= sub("1.15.0"; "1.14.3")' '.files[0].patch |= sub("wanderbound:tag"; "other:tag")'; do
        jq "$change" "$FIXTURES/valid.json" > "$FIXTURES/comparison.json"
        : > "$CALLS"
        run bash "$FIXTURES/image-pr.sh"
        [ "$status" -ne 0 ]
        assert_file_contains "$CALLS" 'pr merge 42 --disable-auto'
        refute_file_contains "$CALLS" 'update-branch'
        refute_file_contains "$CALLS" '--auto'
    done
}

@test "Image PR refuses other authors, forks, branches, drafts and heads that moved during validation" {
    setup_image_pr
    cp "$FIXTURES/pr.json" "$FIXTURES/trusted.json"
    local change
    for change in '.user.login = "someone"' '.head.repo.full_name = "fork/infra"' '.base.ref = "other"' \
        '.head.ref = "other"' '.draft = true' '.state = "closed"' '.head.sha = "new-head"'; do
        jq "$change" "$FIXTURES/trusted.json" > "$FIXTURES/pr.json"
        : > "$CALLS"
        run bash "$FIXTURES/image-pr.sh"
        [ "$status" -ne 0 ]
        refute_file_contains "$CALLS" 'pr merge'
        refute_file_contains "$CALLS" 'update-branch'
    done
}

@test "Image PR propagates GitHub rejection of a stale expected head" {
    setup_image_pr
    run env UPDATE_STATUS=1 bash "$FIXTURES/image-pr.sh"
    [ "$status" -ne 0 ]
    refute_file_contains "$CALLS" '--auto'
    jq '.behind_by = 0' "$FIXTURES/comparison.json" > "$FIXTURES/current.json"
    mv "$FIXTURES/current.json" "$FIXTURES/comparison.json"
    run env MERGE_STATUS=1 bash "$FIXTURES/image-pr.sh"
    [ "$status" -ne 0 ]
    assert_file_contains "$CALLS" '--match-head-commit head'
}
