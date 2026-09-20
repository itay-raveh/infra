#!/usr/bin/env bats
load test_helper/common

setup() {
    setup_repo
    export CHECKER="$REPO_ROOT/scripts/sops-sanity.py"
    export SCANNER_CONFIG="$REPO_ROOT/.betterleaks.toml"
    export SOPS_AGE_KEY_FILE="$BATS_TEST_TMPDIR/age-key"
    unset SOPS_AGE_KEY SOPS_AGE_KEY_CMD
    age-keygen -o "$SOPS_AGE_KEY_FILE" 2>/dev/null
    mkdir -p "$BATS_TEST_TMPDIR/repo/secrets" "$BATS_TEST_TMPDIR/repo/clusters/test"
    cd "$BATS_TEST_TMPDIR/repo" || return
    git init -q
    local recipient
    recipient=$(age-keygen -y "$SOPS_AGE_KEY_FILE")
    printf 'creation_rules:\n  - path_regex: secrets/.*\\.sops\\.yaml$\n    age: %s\n  - path_regex: clusters/.*\\.sops\\.yaml$\n    age: %s\n    encrypted_regex: "^(data|stringData)$"\n' \
        "$recipient" "$recipient" > .sops.yaml
    printf 'password: %s\n' fixture-value |
        sops encrypt --input-type yaml --output-type yaml --filename-override secrets/test.sops.yaml --output secrets/test.sops.yaml
    git add .
}

@test "secret checker accepts genuine ciphertext without access to decryption keys" {
    run env SOPS_AGE_KEY_FILE=/nonexistent python3 "$CHECKER"
    [ "$status" -eq 0 ]
}

@test "secret checker rejects plaintext empty and partial encryption values" {
    cp secrets/test.sops.yaml "$BATS_TEST_TMPDIR/original"
    for expression in '.token = "not-encrypted"' '.password = ""' '.password = null' \
        '.password = "ENC[test]"' '.nested = {"value": "plaintext"}'; do
        cp "$BATS_TEST_TMPDIR/original" secrets/test.sops.yaml
        yq -i "$expression" secrets/test.sops.yaml
        run python3 "$CHECKER"
        [ "$status" -ne 0 ]
        [[ "$output" != *not-encrypted* ]]
        [[ "$output" != *plaintext* ]]
    done
}

@test "secret checker rejects missing metadata extra recipients and encryption overrides" {
    cp secrets/test.sops.yaml "$BATS_TEST_TMPDIR/original"
    for expression in 'del(.sops)' 'del(.sops.mac)' '.sops.mac = "ENC[test]"' \
        '.sops.age += [.sops.age[0]]' '.sops.age[0].recipient = "unexpected"' \
        'del(.sops.age[0].enc)' '.sops.unencrypted_suffix = "_secret"' \
        '.sops.mac_only_encrypted = true'; do
        cp "$BATS_TEST_TMPDIR/original" secrets/test.sops.yaml
        yq -i "$expression" secrets/test.sops.yaml
        run python3 "$CHECKER"
        [ "$status" -ne 0 ]
    done
}

@test "secret checker rejects malformed duplicate and multi-document inputs" {
    cp secrets/test.sops.yaml "$BATS_TEST_TMPDIR/original"
    for extra in 'broken: [' 'password: plaintext' $'---\ntoken: plaintext'; do
        cp "$BATS_TEST_TMPDIR/original" secrets/test.sops.yaml
        printf '\n%s\n' "$extra" >> secrets/test.sops.yaml
        run python3 "$CHECKER"
        [ "$status" -ne 0 ]
        [[ "$output" != *plaintext* ]]
    done
}

@test "secret checker validates staged contents instead of a repaired working copy" {
    cp secrets/test.sops.yaml "$BATS_TEST_TMPDIR/original"
    yq -i '.token = "plaintext"' secrets/test.sops.yaml
    git add secrets/test.sops.yaml
    cp "$BATS_TEST_TMPDIR/original" secrets/test.sops.yaml
    run python3 "$CHECKER" --staged
    [ "$status" -ne 0 ]
    run python3 "$CHECKER"
    [ "$status" -eq 0 ]
}

@test "secret checker checks staged recipients against staged rules" {
    yq -i '.creation_rules[0].age = "unexpected"' .sops.yaml
    run python3 "$CHECKER"
    [ "$status" -ne 0 ]
    run python3 "$CHECKER" --staged
    [ "$status" -eq 0 ]
}

@test "secret checker detects plaintext Secrets in nested Lists and JSON" {
    printf '{"kind":"List","items":[{"kind":"Secret","data":{"token":"cGxhaW4="}}]}' > clusters/test/secret.json
    git add clusters/test/secret.json
    run python3 "$CHECKER"
    [ "$status" -ne 0 ]
}

@test "secret checker accepts encrypted Kubernetes data and rejects changed selectors" {
    printf 'apiVersion: v1\nkind: Secret\nmetadata: {name: fixture}\nstringData: {password: %s}\n' fixture-value |
        sops encrypt --input-type yaml --output-type yaml --filename-override clusters/test/secret.sops.yaml --output clusters/test/secret.sops.yaml
    git add clusters/test/secret.sops.yaml
    run python3 "$CHECKER"
    [ "$status" -eq 0 ]
    yq -i '.sops.encrypted_regex = "^nothing$"' clusters/test/secret.sops.yaml
    run python3 "$CHECKER"
    [ "$status" -ne 0 ]
}

@test "scanner detects a token beside SOPS ciphertext" {
    local token
    token="ghp_$(openssl rand -hex 18)"
    printf 'token: %s\n' "$token" >> secrets/test.sops.yaml
    run betterleaks dir secrets --config "$SCANNER_CONFIG" --redact --no-banner
    [ "$status" -eq 1 ]
    [[ "$output" != *"$token"* ]]
}

@test "scanner accepts ciphertext without skipping encrypted files" {
    run betterleaks dir secrets --config "$SCANNER_CONFIG" --redact --no-banner
    [ "$status" -eq 0 ]
}

@test "vendored image exception cannot hide an additional plaintext Secret value" {
    local target=clusters/shire/infrastructure/controllers/barman-cloud-plugin/manifest.yaml
    mkdir -p "$(dirname "$target")"
    printf 'kind: Secret\ndata:\n  SIDECAR_IMAGE: %s\n' \
        "$(printf 'ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.12.0' | base64 -w0)" > "$target"
    git add "$target"
    run python3 "$CHECKER"
    [ "$status" -eq 0 ]
    printf '  password: %s\n' c2VjcmV0 >> "$target"
    run python3 "$CHECKER"
    [ "$status" -ne 0 ]
}
