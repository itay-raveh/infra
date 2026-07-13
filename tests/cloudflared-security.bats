#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    MANIFEST=clusters/shire/infrastructure/controllers/cloudflared.yaml
    PATCH_FILE="$BATS_TEST_TMPDIR/cloudflared-patch.yaml"
    yq -r 'select(.kind == "HelmRelease") | .spec.postRenderers[0].kustomize.patches[0].patch' "$MANIFEST" > "$PATCH_FILE"
}

@test "keeps restricted Pod Security enforcement on the namespace" {
    run yq -e 'select(.kind == "Namespace" and .metadata.name == "cloudflared") | .metadata.labels."pod-security.kubernetes.io/enforce" == "restricted"' "$MANIFEST"

    [ "$status" -eq 0 ]
}

@test "post-renders a non-root runtime-default pod context" {
    run yq -e '.[] | select(.path == "/spec/template/spec/securityContext") | (.value.runAsNonRoot == true and .value.runAsUser == 65532 and .value.runAsGroup == 65532 and .value.seccompProfile.type == "RuntimeDefault")' "$PATCH_FILE"

    [ "$status" -eq 0 ]
}

@test "post-renders a restricted container context" {
    run yq -e '.[] | select(.path == "/spec/template/spec/containers/0/securityContext") | (.value.allowPrivilegeEscalation == false and .value.readOnlyRootFilesystem == true)' "$PATCH_FILE"
    [ "$status" -eq 0 ]

    run yq -e '.[] | select(.path == "/spec/template/spec/containers/0/securityContext") | .value.capabilities.drop | select(length == 1 and .[0] == "ALL")' "$PATCH_FILE"
    [ "$status" -eq 0 ]
}

@test "troubleshooting uses the Helm deployment name" {
    run grep -En 'deploy/cloudflared-cloudflared' docs/troubleshooting.md
    [ "$status" -eq 0 ]

    run grep -En 'deploy/cloudflared([^[:alnum:]-]|$)' docs/troubleshooting.md
    [ "$status" -eq 1 ]
}
