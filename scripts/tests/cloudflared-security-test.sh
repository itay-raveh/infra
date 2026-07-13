#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

readonly manifest=clusters/shire/infrastructure/controllers/cloudflared.yaml
readonly troubleshooting=docs/troubleshooting.md

assert_contains() {
    local pattern=$1
    local message=$2

    if ! grep -Eq -- "$pattern" "$manifest"; then
        printf 'FAIL: %s\n' "$message" >&2
        exit 1
    fi
}

assert_contains 'pod-security\.kubernetes\.io/enforce:[[:space:]]*restricted' \
    'the cloudflared namespace must retain restricted Pod Security enforcement'
assert_contains 'postRenderers:' \
    'the Helm release must post-render the third-party chart'
assert_contains 'path:[[:space:]]*/spec/template/spec/securityContext' \
    'the post-renderer must set a pod security context'
assert_contains 'runAsNonRoot:[[:space:]]*true' \
    'cloudflared must be required to run as a non-root user'
assert_contains 'runAsUser:[[:space:]]*65532' \
    'cloudflared must use the numeric non-root user from the upstream image'
assert_contains 'runAsGroup:[[:space:]]*65532' \
    'cloudflared must use the numeric non-root group from the upstream image'
assert_contains 'seccompProfile:' \
    'cloudflared must use an explicit seccomp profile'
assert_contains 'type:[[:space:]]*RuntimeDefault' \
    'cloudflared must use the runtime-default seccomp profile'
assert_contains 'path:[[:space:]]*/spec/template/spec/containers/0/securityContext' \
    'the post-renderer must set the container security context'
assert_contains 'allowPrivilegeEscalation:[[:space:]]*false' \
    'cloudflared must prohibit privilege escalation'
assert_contains 'readOnlyRootFilesystem:[[:space:]]*true' \
    'cloudflared must use a read-only root filesystem'
assert_contains 'drop:' \
    'cloudflared must drop Linux capabilities'
assert_contains '-[[:space:]]*ALL' \
    'cloudflared must drop all Linux capabilities'

if ! grep -Fq 'deploy/cloudflared-cloudflared' "$troubleshooting"; then
    printf 'FAIL: troubleshooting must use the Helm release deployment name\n' >&2
    exit 1
fi
if grep -Eq 'deploy/cloudflared([^[:alnum:]-]|$)' "$troubleshooting"; then
    printf 'FAIL: troubleshooting must not use the nonexistent cloudflared deployment name\n' >&2
    exit 1
fi

printf 'cloudflared restricted Pod Security invariants passed\n'
