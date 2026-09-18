#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_sops_fixture
}

@test "preserves literal credentials and argument boundaries across multiple files" {
    credential="\$(touch injected); \`id\` \$HOME 'quoted' \\path"
    encrypt_fixture first.sops.yaml "$(jq -n --arg value "$credential" '{TEST_CREDENTIAL: $value}')"
    encrypt_fixture second.sops.yaml '{"SECOND_CREDENTIAL":"second"}'
    export ARGS_CAPTURE="$BATS_TEST_TMPDIR/args"
    export VALUE_CAPTURE="$BATS_TEST_TMPDIR/value"
    args=('' 'a b' "a'b" '"quoted"' "\$HOME" "\$(touch injected)" $'line\nnext' '*.tf')
    printf '%s\0' "${args[@]}" > expected-args

    run bash "$REPO_ROOT/scripts/sops-exec.sh" first.sops.yaml second.sops.yaml -- \
        bash -c 'printf "%s\0" "$@" > "$ARGS_CAPTURE"; printf "%s" "$TEST_CREDENTIAL" > "$VALUE_CAPTURE"; [[ "$SECOND_CREDENTIAL" == second ]]' \
        _ "${args[@]}"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
    cmp expected-args "$ARGS_CAPTURE"
    sops decrypt --extract '["TEST_CREDENTIAL"]' first.sops.yaml > expected-value
    cmp expected-value "$VALUE_CAPTURE"
    [ ! -e injected ]
    [ -z "${TEST_CREDENTIAL+x}" ]
}

@test "does not launch the command when a later file fails authentication" {
    encrypt_fixture first.sops.yaml '{"FIRST_CREDENTIAL":"first"}'
    encrypt_fixture second.sops.yaml '{"SECOND_CREDENTIAL":"second"}'
    sed -i 's/SECOND_CREDENTIAL/RENAMED_CREDENTIAL/' second.sops.yaml

    run bash "$REPO_ROOT/scripts/sops-exec.sh" first.sops.yaml second.sops.yaml -- touch launched

    [ "$status" -ne 0 ]
    [ ! -e launched ]
}

@test "propagates the command exit status" {
    encrypt_fixture first.sops.yaml '{"FIRST_CREDENTIAL":"first"}'
    run bash "$REPO_ROOT/scripts/sops-exec.sh" first.sops.yaml -- sh -c 'exit 37'
    [ "$status" -eq 37 ]
}

@test "rejects empty required values even when a stale environment value exists" {
    encrypt_fixture first.sops.yaml '{"FIRST_CREDENTIAL":""}'
    run env FIRST_CREDENTIAL=stale bash "$REPO_ROOT/scripts/sops-exec.sh" first.sops.yaml -- touch launched
    [ "$status" -ne 0 ]
    [ ! -e launched ]
}

@test "rejects a missing file before decrypting or launching" {
    run bash "$REPO_ROOT/scripts/sops-exec.sh" missing.sops.yaml -- touch launched
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing encrypted file"* ]]
    [ ! -e launched ]
}
