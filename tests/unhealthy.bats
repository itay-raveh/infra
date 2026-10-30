#!/usr/bin/env bats
load test_helper/common

setup() {
    setup_repo
    setup_fakebin
    export PODS_FIXTURE="$BATS_TEST_TMPDIR/pods.json"
    cat > "$FAKEBIN/kubectl" <<'SH'
#!/usr/bin/env bash
[[ ${FAIL_KUBECTL:-0} != 1 ]] || exit 17
cat "$PODS_FIXTURE"
SH
    chmod +x "$FAKEBIN/kubectl"
}

@test "unhealthy includes crashing and unready running pods but excludes healthy and completed pods" {
    jq -n '{items: [
        {metadata: {namespace: "apps", name: "healthy"}, status: {phase: "Running", conditions: [{type: "Ready", status: "True"}]}},
        {metadata: {namespace: "apps", name: "crashing"}, status: {phase: "Running", conditions: [{type: "Ready", status: "False"}], containerStatuses: [{state: {waiting: {reason: "CrashLoopBackOff"}}}]}},
        {metadata: {namespace: "apps", name: "pending"}, status: {phase: "Pending"}},
        {metadata: {namespace: "apps", name: "unknown"}, status: {phase: "Running"}},
        {metadata: {namespace: "apps", name: "failed"}, status: {phase: "Failed"}},
        {metadata: {namespace: "apps", name: "completed"}, status: {phase: "Succeeded"}}
    ]}' > "$PODS_FIXTURE"
    run bash scripts/unhealthy.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *CrashLoopBackOff* && "$output" == *pending* && "$output" == *unknown* && "$output" == *failed* ]]
    [[ "$output" != *healthy* && "$output" != *completed* ]]
    [ "${#lines[@]}" -eq 5 ]
}

@test "unhealthy propagates Kubernetes API failures" {
    export FAIL_KUBECTL=1
    run bash scripts/unhealthy.sh
    [ "$status" -eq 17 ]
}
