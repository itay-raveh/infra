#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_sops_fixture
    export TARGET="$BATS_TEST_TMPDIR/secret.sops.yaml"
    encrypt_fixture "$TARGET" '{"previous":"unchanged"}'
    cp "$TARGET" previous
}

@test "encrypts a generated Secret and preserves multiline token contents" {
    run bash "$REPO_ROOT/scripts/refresh-sops-secret.sh" "$TARGET" test service token -- \
        printf 'first\nsecond\n'

    [ "$status" -eq 0 ]
    sops decrypt --output-type json "$TARGET" | jq -e '
        .apiVersion == "v1" and .kind == "Secret" and
        .metadata == {namespace: "test", name: "service"} and
        (.data.token | @base64d) == "first\nsecond\n"
    ' >/dev/null
    refute_file_contains "$TARGET" first
    [ "$(stat -c '%a' "$TARGET")" = 600 ]
}

@test "retains previous ciphertext when a producer returns partial output then fails" {
    run bash "$REPO_ROOT/scripts/refresh-sops-secret.sh" "$TARGET" test service token -- \
        sh -c 'printf partial; exit 9'

    [ "$status" -ne 0 ]
    cmp previous "$TARGET"
    [ "$(find . -name 'secret.sops.yaml.*' | wc -l)" -eq 0 ]
}

@test "retains previous ciphertext when encryption fails after writing output" {
    setup_fakebin
    cat > "$FAKEBIN/sops" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf partial-ciphertext
exit 7
EOF
    make_executable "$FAKEBIN/sops"

    run bash "$REPO_ROOT/scripts/refresh-sops-secret.sh" "$TARGET" test service token -- printf value

    [ "$status" -ne 0 ]
    cmp previous "$TARGET"
    [ "$(find . -name 'secret.sops.yaml.*' | wc -l)" -eq 0 ]
}

@test "rejects an empty token without replacing the destination" {
    run bash "$REPO_ROOT/scripts/refresh-sops-secret.sh" "$TARGET" test service token -- printf ''
    [ "$status" -ne 0 ]
    cmp previous "$TARGET"
}

@test "does not create a destination when the producer fails" {
    rm "$TARGET"
    run bash "$REPO_ROOT/scripts/refresh-sops-secret.sh" "$TARGET" test service token -- false
    [ "$status" -ne 0 ]
    [ ! -e "$TARGET" ]
}
