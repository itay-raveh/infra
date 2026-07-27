#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    setup_fakebin
    export TEST_CALLS="$BATS_TEST_TMPDIR/calls.log"

    cat > "$FAKEBIN/flux" <<'EOF'
#!/usr/bin/env bash
printf 'flux %s\n' "$*" >> "$TEST_CALLS"
EOF

    cat > "$FAKEBIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "$TEST_CALLS"
case "$*" in
    *'get helmrelease wanderbound -o jsonpath={.status.history[0].appVersion}'*)
        printf '%s' "${TEST_APP_VERSION:-1.13.0}"
        ;;
    *'get deployment wanderbound -o jsonpath={.spec.template.spec.containers[?(@.name=="wanderbound")].image}'*)
        printf 'ghcr.io/itay-raveh/wanderbound:%s' "${TEST_IMAGE_VERSION:-1.13.0}"
        ;;
    *'get deployment wanderbound -o jsonpath={.spec.template.spec.initContainers[*].name}'*)
        printf '%s' "${TEST_INIT_CONTAINERS:-sourcemaps}"
        ;;
esac
EOF

    cat > "$FAKEBIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$TEST_CALLS"
if [[ "$*" == *'/api/v1/health'* ]]; then
    printf '{"db":true,"disk":true,"playwright":true}\n'
else
    printf '<html>Wanderbound</html>\n'
fi
EOF

    make_executable "$FAKEBIN/flux"
    make_executable "$FAKEBIN/kubectl"
    make_executable "$FAKEBIN/curl"
}

@test "release verification checks reconciliation, workload identity, and public health" {
    run bash scripts/verify-wanderbound-deployment.sh 1.13.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Wanderbound 1.13.0 deployment verified."* ]]
    assert_file_contains "$TEST_CALLS" "flux reconcile source oci wanderbound-chart --namespace wanderbound"
    assert_file_contains "$TEST_CALLS" "flux reconcile helmrelease wanderbound --namespace wanderbound"
    assert_file_contains "$TEST_CALLS" "kubectl --namespace wanderbound rollout status deployment/wanderbound"
    assert_file_contains "$TEST_CALLS" "curl --fail --silent --show-error https://wanderbound.raveh.dev/api/v1/health"
}

@test "release verification rejects a stale deployment image" {
    run env TEST_IMAGE_VERSION=1.12.0 bash scripts/verify-wanderbound-deployment.sh 1.13.0

    [ "$status" -ne 0 ]
    [[ "$output" == *"expected image"* ]]
}

@test "release verification rejects the removed migrations init container" {
    run env TEST_INIT_CONTAINERS="sourcemaps migrations" bash scripts/verify-wanderbound-deployment.sh 1.13.0

    [ "$status" -ne 0 ]
    [[ "$output" == *"migrations init container"* ]]
}

@test "HelmRelease retries failed upgrades and rolls back the last failure" {
    query='select(.kind == "HelmRelease") | .spec.upgrade.remediation'
    [ "$(yq "$query | .retries" clusters/shire/apps/wanderbound/app-chart.yaml)" -eq 1 ]
    [ "$(yq "$query | .strategy" clusters/shire/apps/wanderbound/app-chart.yaml)" = rollback ]
    [ "$(yq "$query | .remediateLastFailure" clusters/shire/apps/wanderbound/app-chart.yaml)" = true ]
}
