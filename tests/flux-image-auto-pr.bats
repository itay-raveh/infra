#!/usr/bin/env bats
load test_helper/common

@test "Flux image PR refresh respects validated diffs, head races and required checks" {
    setup_repo
    run python3 tests/flux_image_auto_pr_test.py
    [ "$status" -eq 0 ]
}
