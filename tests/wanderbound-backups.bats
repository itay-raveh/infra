#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    setup_fakebin
    export TEST_CALLS="$BATS_TEST_TMPDIR/calls.log"
    export TEST_MANIFESTS="$BATS_TEST_TMPDIR/manifests.yaml"

    cat > "$FAKEBIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "$TEST_CALLS"
if [[ "$*" == *'apply -f -'* ]]; then
    cat >> "$TEST_MANIFESTS"
elif [[ "$*" == *'cnpg psql'* ]]; then
    printf 't\n'
elif [[ "$*" == *'logs job/'* ]]; then
    printf 'repository restored successfully\n'
fi
EOF

    make_executable "$FAKEBIN/kubectl"
}

@test "backup verification restores the database and app data into disposable resources" {
    run bash scripts/verify-wanderbound-backups.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Wanderbound database and app-data restores verified."* ]]
    assert_file_contains "$TEST_MANIFESTS" "source: wanderbound-backup-source"
    assert_file_contains "$TEST_MANIFESTS" "barmanObjectName: wanderbound-backup"
    assert_file_contains "$TEST_MANIFESTS" "restic restore latest --target /restore"
    assert_file_contains "$TEST_CALLS" "cnpg psql"
    assert_file_contains "$TEST_CALLS" "wait --for=condition=complete job/"
    assert_file_contains "$TEST_CALLS" "delete cluster"
    assert_file_contains "$TEST_CALLS" "delete pvc"
}
