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
