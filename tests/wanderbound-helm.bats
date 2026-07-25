#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    APP_DIR=clusters/shire/apps/wanderbound
    KUSTOMIZATION=$APP_DIR/kustomization.yaml
    CHART=$APP_DIR/app-chart.yaml
    MIGRATION=$APP_DIR/HELM_MIGRATION.md
}

@test "replaces raw application resources with the chart release" {
    run yq -e '.resources | contains(["app-chart.yaml"])' "$KUSTOMIZATION"
    [ "$status" -eq 0 ]

    for raw_resource in app-config.yaml app-deployment.yaml app-service.yaml app-data-pvc.yaml; do
        run yq -e ".resources | contains([\"$raw_resource\"])" "$KUSTOMIZATION"
        [ "$status" -eq 1 ]
        [ ! -e "$APP_DIR/$raw_resource" ]
    done
}

@test "tracks the public chart with the existing release policy" {
    run yq -e 'select(.kind == "OCIRepository") |
        .apiVersion == "source.toolkit.fluxcd.io/v1" and
        .metadata.name == "wanderbound-chart" and
        .metadata.namespace == "wanderbound" and
        .spec.url == "oci://ghcr.io/itay-raveh/charts/wanderbound" and
        .spec.ref.tag == "1.10.0"' "$CHART"
    [ "$status" -eq 0 ]

    image_policy_key="\$imagepolicy"
    grep -Fq "# {\"$image_policy_key\": \"flux-system:wanderbound:tag\"}" "$CHART"
}

@test "installs the chart in the existing namespace without a second image version" {
    run yq -e 'select(.kind == "HelmRelease") |
        .apiVersion == "helm.toolkit.fluxcd.io/v2" and
        .metadata.name == "wanderbound" and
        .metadata.namespace == "wanderbound" and
        .spec.chartRef.kind == "OCIRepository" and
        .spec.chartRef.name == "wanderbound-chart" and
        .spec.install.createNamespace == false and
        .spec.values.image == null' "$CHART"
    [ "$status" -eq 0 ]
}

@test "preserves the current instance values and secret wiring" {
    run yq ea -rN 'select(.kind == "HelmRelease") | .spec.values |
        [
            .config.ENVIRONMENT,
            .config.PUBLIC_URL,
            .config.DATA_FOLDER,
            .existingSecrets[0],
            .existingSecrets[1],
            .secretEnv.SQLALCHEMY_DATABASE_URI.secretName,
            .secretEnv.SQLALCHEMY_DATABASE_URI.key,
            .resources.requests.cpu,
            .resources.requests.memory,
            .resources.limits.cpu,
            .resources.limits.memory,
            .persistence.size,
            .persistence.storageClass,
            .persistence.retain,
            .ingress.enabled,
            .sourceMaps.enabled,
            .sourceMaps.existingSecret
        ] | @tsv' "$CHART"
    [ "$status" -eq 0 ]
    [ "$output" = $'production\thttps://wanderbound.raveh.dev\tnull\twanderbound-secrets\twanderbound-upload-s3-creds\twanderbound-db-app\turi\t500m\t512Mi\t2\t2Gi\t50Gi\thcloud-volumes\ttrue\tfalse\ttrue\twanderbound-sourcemaps-secrets' ]
}

@test "keeps supporting infrastructure outside the application chart" {
    for resource in \
        namespace.yaml \
        cnpg-s3-creds.sops.yaml \
        objectstore.yaml \
        wanderbound-db.yaml \
        wanderbound-db-scheduled-backup.yaml \
        wanderbound-secrets.sops.yaml \
        wanderbound-upload-s3-creds.sops.yaml \
        wanderbound-sourcemaps-secrets.sops.yaml \
        wanderbound-backup-secrets.sops.yaml \
        rate-limit.yaml \
        ingressroute.yaml \
        data-backup.yaml \
        image-automation.yaml; do
        run yq -e ".resources | contains([\"$resource\"])" "$KUSTOMIZATION"
        [ "$status" -eq 0 ]
    done
}

@test "documents a staged ownership handoff that protects the existing volume" {
    assert_file_contains "$MIGRATION" "kubectl get persistentvolumeclaim wanderbound-app-data"
    assert_file_contains "$MIGRATION" "meta.helm.sh/release-name=wanderbound"
    assert_file_contains "$MIGRATION" "meta.helm.sh/release-namespace=wanderbound"
    assert_file_contains "$MIGRATION" "app.kubernetes.io/managed-by=Helm"
    assert_file_contains "$MIGRATION" "kustomize.toolkit.fluxcd.io/prune=disabled"
    assert_file_contains "$MIGRATION" "uid"
    assert_file_contains "$MIGRATION" "volumeName"
    assert_file_contains "$MIGRATION" "Do not continue"
}
