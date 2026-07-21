#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    APP_DIR=clusters/shire/apps/wanderbound
}

@test "deploys one Wanderbound application workload and service" {
    [ -f "$APP_DIR/app-deployment.yaml" ]
    [ -f "$APP_DIR/app-service.yaml" ]
    [ ! -e "$APP_DIR/backend-deployment.yaml" ]
    [ ! -e "$APP_DIR/backend-service.yaml" ]
    [ ! -e "$APP_DIR/frontend-deployment.yaml" ]
    [ ! -e "$APP_DIR/frontend-service.yaml" ]

    [ "$(yq '.spec.template.spec.containers | length' "$APP_DIR/app-deployment.yaml")" -eq 1 ]
    [ "$(yq '.spec.template.spec.initContainers | length' "$APP_DIR/app-deployment.yaml")" -eq 2 ]
    [ "$(yq '.spec.ports[0].port' "$APP_DIR/app-service.yaml")" -eq 8000 ]
}

@test "uploads matching source maps before migrations and app startup" {
    [ "$(yq '.spec.template.spec.initContainers[0].name' "$APP_DIR/app-deployment.yaml")" = "sourcemaps" ]
    [ "$(yq '.spec.template.spec.initContainers[1].name' "$APP_DIR/app-deployment.yaml")" = "migrations" ]
    [ "$(yq '.spec.template.spec.initContainers[0].image' "$APP_DIR/app-deployment.yaml")" = "ghcr.io/itay-raveh/wanderbound-sourcemaps" ]
    [ "$(yq '.spec.template.spec.initContainers[0].envFrom[0].secretRef.name' "$APP_DIR/app-deployment.yaml")" = "wanderbound-sourcemaps-secrets" ]
    [ "$(yq '.spec.template.spec.initContainers[0].env[] | select(.name == "SENTRY_ORG") | .valueFrom.configMapKeyRef.name' "$APP_DIR/app-deployment.yaml")" = "wanderbound-config" ]
    [ "$(yq '.spec.template.spec.initContainers[0].env[] | select(.name == "SENTRY_PROJECT") | .valueFrom.configMapKeyRef.name' "$APP_DIR/app-deployment.yaml")" = "wanderbound-config" ]

    run yq -e '.spec.template.spec.containers[] | select(.name == "app") | .envFrom[]? | select(.secretRef.name == "wanderbound-sourcemaps-secrets")' "$APP_DIR/app-deployment.yaml"
    [ "$status" -ne 0 ]
}

@test "uses one image policy for migrations and the application" {
    application_image=$(yq '.spec.template.spec.containers[0].image' "$APP_DIR/app-deployment.yaml")
    [ "$(yq '.spec.template.spec.initContainers[] | select(.name == "migrations") | .image' "$APP_DIR/app-deployment.yaml")" = "$application_image" ]

    application_tag=$(yq '.images[] | select(.name == "ghcr.io/itay-raveh/wanderbound") | .newTag' "$APP_DIR/kustomization.yaml")
    sourcemaps_tag=$(yq '.images[] | select(.name == "ghcr.io/itay-raveh/wanderbound-sourcemaps") | .newTag' "$APP_DIR/kustomization.yaml")
    [ "$application_tag" = "1.8.0" ]
    [ "$sourcemaps_tag" = "$application_tag" ]

    [ "$(yq 'select(.kind == "ImageRepository") | .metadata.name' "$APP_DIR/image-automation.yaml")" = "wanderbound" ]
    [ "$(yq 'select(.kind == "ImagePolicy") | .spec.filterTags.pattern' "$APP_DIR/image-automation.yaml")" = '^[0-9]+\.[0-9]+\.[0-9]+$' ]
    [ "$(yq 'select(.kind == "ImagePolicy") | .spec.policy.semver.range' "$APP_DIR/image-automation.yaml")" = '>=0.0.0' ]
    [ "$(yq 'select(.kind == "ImagePolicy") | .spec.digestReflectionPolicy' "$APP_DIR/image-automation.yaml")" = "IfNotPresent" ]
}

@test "loads instance values without legacy Vite names" {
    grep -q 'name: wanderbound-config' "$APP_DIR/app-config.yaml"
    grep -q 'name: wanderbound-config' "$APP_DIR/app-deployment.yaml"
    grep -q 'name: wanderbound-secrets' "$APP_DIR/app-deployment.yaml"
    grep -q 'name: wanderbound-upload-s3-creds' "$APP_DIR/app-deployment.yaml"

    run grep -R 'VITE_' "$APP_DIR"
    [ "$status" -eq 1 ]
}

@test "keeps hosted request limits in Traefik" {
    [ "$(yq 'select(.metadata.name == "wanderbound-demo-limit") | .spec.rateLimit.average' "$APP_DIR/rate-limit.yaml")" -eq 2 ]
    [ "$(yq 'select(.metadata.name == "wanderbound-demo-limit") | .spec.rateLimit.period' "$APP_DIR/rate-limit.yaml")" = "1m" ]
    [ "$(yq 'select(.metadata.name == "wanderbound-demo-limit") | .spec.rateLimit.burst' "$APP_DIR/rate-limit.yaml")" -eq 2 ]
    [ "$(yq 'select(.metadata.name == "wanderbound-media-limit") | .spec.rateLimit.average' "$APP_DIR/rate-limit.yaml")" -eq 60 ]
    [ "$(yq 'select(.metadata.name == "wanderbound-media-limit") | .spec.rateLimit.burst' "$APP_DIR/rate-limit.yaml")" -eq 120 ]
    [ "$(yq 'select(.metadata.name == "wanderbound-api-limit") | .spec.rateLimit.average' "$APP_DIR/rate-limit.yaml")" -eq 10 ]
    [ "$(yq 'select(.metadata.name == "wanderbound-api-limit") | .spec.rateLimit.burst' "$APP_DIR/rate-limit.yaml")" -eq 30 ]

    [ "$(yq -N 'select(.kind == "Middleware") | .spec.rateLimit.sourceCriterion.requestHeaderName' "$APP_DIR/rate-limit.yaml" | sort -u)" = "CF-Connecting-IP" ]
    [ "$(yq '.spec.routes[].services[0].name' "$APP_DIR/ingressroute.yaml" | sort -u)" = "wanderbound-app" ]
}
