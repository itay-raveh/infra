#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
}

@test "Cloudflare spending guard handles budgets, failures, and recovery" {
    node --test tests/cloudflare-spending-guard.test.mjs
}
