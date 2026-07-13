setup_repo() {
    REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    cd "$REPO_ROOT" || return
    export REPO_ROOT
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
