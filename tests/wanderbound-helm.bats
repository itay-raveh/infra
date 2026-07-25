#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper/common

setup() {
    setup_repo
    CHART=clusters/shire/apps/wanderbound/app-chart.yaml
    VALUES="$BATS_TEST_TMPDIR/values.yaml"
    RENDERED="$BATS_TEST_TMPDIR/rendered.yaml"
}

@test "the pinned chart renders the Shire deployment contract" {
    chart_url=$(yq -r 'select(.kind == "OCIRepository") | .spec.url' "$CHART")
    chart_version=$(yq -r 'select(.kind == "OCIRepository") | .spec.ref.tag' "$CHART")
    yq 'select(.kind == "HelmRelease") | .spec.values' "$CHART" > "$VALUES"

    run --separate-stderr helm template wanderbound "$chart_url" \
        --version "$chart_version" \
        --namespace wanderbound \
        --values "$VALUES"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" > "$RENDERED"

    CHART_VERSION="$chart_version" yq -e '
        select(.kind == "Deployment" and .metadata.name == "wanderbound") |
        .spec.template.spec.containers[] | select(.name == "wanderbound") |
        .image == ("ghcr.io/itay-raveh/wanderbound:" + strenv(CHART_VERSION))
    ' "$RENDERED"

    for secret_name in wanderbound-secrets wanderbound-upload-s3-creds; do
        SECRET_NAME="$secret_name" yq -e '
            select(.kind == "Deployment" and .metadata.name == "wanderbound") |
            .spec.template.spec.containers[] | select(.name == "wanderbound") |
            .envFrom[] | select(.secretRef.name == strenv(SECRET_NAME))
        ' "$RENDERED"
    done

    yq -e '
        select(.kind == "Deployment" and .metadata.name == "wanderbound") |
        .spec.template.spec.containers[] | select(.name == "wanderbound") |
        .env[] | select(.name == "SQLALCHEMY_DATABASE_URI") |
        select(
            .valueFrom.secretKeyRef.name == "wanderbound-db-app" and
            .valueFrom.secretKeyRef.key == "uri"
        )
    ' "$RENDERED"

    yq -e '
        select(.kind == "Deployment" and .metadata.name == "wanderbound") |
        .spec.template.spec.initContainers[] | select(.name == "sourcemaps") |
        .envFrom[] | select(.secretRef.name == "wanderbound-sourcemaps-secrets")
    ' "$RENDERED"

    yq -e '
        select(.kind == "PersistentVolumeClaim" and .metadata.name == "wanderbound-app-data") |
        (.metadata.namespace == "wanderbound") and
        (.metadata.annotations."helm.sh/resource-policy" == "keep") and
        (.spec.storageClassName == "hcloud-volumes") and
        (.spec.resources.requests.storage == "50Gi")
    ' "$RENDERED"
}
