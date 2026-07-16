#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    MISE_CONFIG=mise.toml
}

@test "pins the CloudNativePG kubectl plugin" {
    grep -Fq '"aqua:cloudnative-pg/cloudnative-pg/kubectl-cnpg" = "1.29.2"' "$MISE_CONFIG"
}

@test "opens the Wanderbound database on the primary with an interactive terminal" {
    task_block=$(awk '
        /^\[tasks\."wanderbound:psql"\]$/ { found = 1; next }
        /^\[/ && found { exit }
        found
    ' "$MISE_CONFIG")

    [[ "$task_block" == *'run = "kubectl cnpg psql -n wanderbound wanderbound-db -- wanderbound"'* ]]
    [[ "$task_block" == *'raw = true'* ]]
}
