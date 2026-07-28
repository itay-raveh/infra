#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    setup_fakebin

    export TF_VAR_ssh_public_key_path="$BATS_TEST_TMPDIR/id_ed25519_sk.pub"
    printf 'ssh-ed25519 test\n' > "$TF_VAR_ssh_public_key_path"
    export TEST_SIGNING_KEY="$BATS_TEST_TMPDIR/signing-key.pub"
    printf 'ssh-ed25519 signing-test\n' > "$TEST_SIGNING_KEY"

    for command in mise kubectl flux wg wg-quick sudo install systemctl; do
        printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/$command"
        make_executable "$FAKEBIN/$command"
    done

cat > "$FAKEBIN/yq" <<'EOF'
#!/bin/sh
case "$*" in
    *spec.url*) printf 'https://github.com/itay-raveh/infra.git\n' ;;
    *) printf 'main\n' ;;
esac
EOF

    cat > "$FAKEBIN/git" <<'EOF'
#!/bin/sh
case "$*" in
    "status --porcelain") ;;
    "rev-parse --abbrev-ref @{upstream}") printf '%s\n' "${TEST_GIT_UPSTREAM:-origin/main}" ;;
    "branch --show-current") printf '%s\n' "${TEST_GIT_BRANCH:-main}" ;;
    "remote get-url --push origin") printf '%s\n' "${TEST_ORIGIN_URL:-https://github.com/itay-raveh/infra.git}" ;;
    "config --bool --get commit.gpgsign") printf 'true\n' ;;
    "config --get gpg.format") printf 'ssh\n' ;;
    "config --path --get user.signingkey") printf '%s\n' "$TEST_SIGNING_KEY" ;;
esac
EOF

    cat > "$FAKEBIN/gh" <<'EOF'
#!/bin/sh
case "$*" in
    "api repos/{owner}/{repo} --jq "*) printf '%s\n' "${TEST_GITHUB_ACCESS:-true}" ;;
    "api repos/{owner}/{repo}/rulesets --jq "*) printf '1\n' ;;
    "api repos/{owner}/{repo}/rulesets/1 --jq "*) printf 'true\n' ;;
esac
EOF

    cat > "$FAKEBIN/ssh-keygen" <<'EOF'
#!/bin/sh
exit "${TEST_SIGNING_STATUS:-0}"
EOF

    cat > "$FAKEBIN/ykman" <<'EOF'
#!/bin/sh
printf '12345678\n'
EOF

    cat > "$FAKEBIN/sops" <<'EOF'
#!/bin/sh
case " $* " in
    *" --output-type dotenv "*)
        printf 'TF_VAR_encryption_passphrase=test\n'
        ;;
esac
EOF

    cat > "$FAKEBIN/tofu" <<'EOF'
#!/bin/sh
exit 0
EOF

    make_executable "$FAKEBIN/ykman"
    make_executable "$FAKEBIN/sops"
    make_executable "$FAKEBIN/tofu"
    make_executable "$FAKEBIN/git"
    make_executable "$FAKEBIN/gh"
    make_executable "$FAKEBIN/ssh-keygen"
    make_executable "$FAKEBIN/yq"
}

@test "passes when every rebuild prerequisite is available" {
    run env PATH="$FAKEBIN" /bin/bash scripts/doctor.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"all rebuild prerequisites are ready"* ]]
}

@test "reports every failed external prerequisite in one run" {
    cat > "$FAKEBIN/ykman" <<'EOF'
#!/bin/sh
exit 1
EOF

    cat > "$FAKEBIN/sops" <<'EOF'
#!/bin/sh
case "$*" in
    *bootstrap/cluster-age-key.sops.txt*) exit 1 ;;
    *"--output-type dotenv"*) printf 'TF_VAR_encryption_passphrase=test\n' ;;
esac
EOF

    cat > "$FAKEBIN/tofu" <<'EOF'
#!/bin/sh
case "$*" in
    *"state pull"*) exit 1 ;;
esac
EOF

    run env PATH="$FAKEBIN" /bin/bash scripts/doctor.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"YubiKey is not connected"* ]]
    [[ "$output" == *"cannot decrypt bootstrap/cluster-age-key.sops.txt"* ]]
    [[ "$output" == *"cannot access the OpenTofu state backend"* ]]
    [[ "$output" == *"3 problems found"* ]]
}

@test "does not run a hardware probe when ykman is unavailable" {
    rm "$FAKEBIN/ykman"

    run env PATH="$FAKEBIN" /bin/bash scripts/doctor.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"ykman is not available"* ]]
    [[ "$output" != *"YubiKey is not connected"* ]]
    [[ "$output" == *"1 problems found"* ]]
}

@test "rejects a branch that Flux does not reconcile" {
    run env PATH="$FAKEBIN" TEST_GIT_BRANCH=feature TEST_GIT_UPSTREAM=origin/feature \
        /bin/bash scripts/doctor.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"current branch feature does not match Flux branch main"* ]]
}

@test "fails when the configured signing key cannot sign" {
    run env PATH="$FAKEBIN" TEST_SIGNING_STATUS=1 /bin/bash scripts/doctor.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"configured SSH signing key cannot sign"* ]]
}

@test "fails when the authenticated GitHub account lacks admin push access" {
    run env PATH="$FAKEBIN" TEST_GITHUB_ACCESS=false /bin/bash scripts/doctor.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"authenticated GitHub account lacks admin push access"* ]]
}

@test "rejects an origin push URL that bypasses GitHub CLI authentication" {
    run env PATH="$FAKEBIN" TEST_ORIGIN_URL=git@github.com:itay-raveh/infra.git \
        /bin/bash scripts/doctor.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"origin push URL does not use the Flux HTTPS repository"* ]]
}
