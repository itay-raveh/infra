setup_repo() {
    REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    cd "$REPO_ROOT" || return
    export REPO_ROOT
}

setup_script_repo() {
    local source_root
    source_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    REPO_ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO_ROOT/secrets"
    cp -R "$source_root/scripts" "$REPO_ROOT/scripts"
    cat > "$REPO_ROOT/secrets/state.sops.yaml" <<'EOF'
TF_VAR_encryption_passphrase: ENC[test]
AWS_ACCESS_KEY_ID: ENC[test]
AWS_SECRET_ACCESS_KEY: ENC[test]
EOF
    cat > "$REPO_ROOT/secrets/wireguard.sops.yaml" <<'EOF'
TF_VAR_wireguard_server_private_key: ENC[test]
TF_VAR_wireguard_workstation_public_key: ENC[test]
EOF
    cat > "$REPO_ROOT/secrets/workstation.sops.yaml" <<'EOF'
WIREGUARD_WORKSTATION_PRIVATE_KEY: ENC[test]
EOF
    cat > "$REPO_ROOT/secrets/tofu.sops.yaml" <<'EOF'
TF_VAR_hcloud_token: ENC[test]
TF_VAR_cloudflare_api_token: ENC[test]
EOF
    cd "$REPO_ROOT" || return
    export REPO_ROOT
}

setup_sops_fixture() {
    setup_repo
    export SOPS_AGE_KEY_FILE="$BATS_TEST_TMPDIR/age-key.txt"
    unset SOPS_AGE_KEY SOPS_AGE_KEY_CMD
    age-keygen -o "$SOPS_AGE_KEY_FILE" 2>/dev/null
    local recipient
    recipient=$(age-keygen -y "$SOPS_AGE_KEY_FILE")
    printf 'creation_rules:\n  - age: %s\n' "$recipient" > "$BATS_TEST_TMPDIR/.sops.yaml"
    cd "$BATS_TEST_TMPDIR" || return
}

encrypt_fixture() {
    local filename=${1##*/}
    printf '%s' "$2" | sops encrypt --input-type json --output-type yaml \
        --filename-override "$filename" > "$1"
}

setup_fakebin() {
    FAKEBIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKEBIN"
    PATH="$FAKEBIN:$PATH"
    export FAKEBIN PATH
}

make_executable() {
    chmod +x "$1"
}

assert_file_contains() {
    grep -Fq -- "$2" "$1"
}

refute_file_contains() {
    ! grep -Fq -- "$2" "$1"
}
