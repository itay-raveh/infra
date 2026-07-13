#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    LIFECYCLE=tofu/wanderbound_uploads.tf
}

@test "manages Wanderbound upload lifecycle through the AWS S3 API" {
    grep -Eq 'resource "aws_s3_bucket_lifecycle_configuration" "wanderbound_uploads"' "$LIFECYCLE"
    grep -Eq 'provider[[:space:]]*=[[:space:]]*aws\.hetzner_object_storage' "$LIFECYCLE"
    grep -Eq 'days_after_initiation[[:space:]]*=[[:space:]]*2' "$LIFECYCLE"
    grep -Eq 'days[[:space:]]*=[[:space:]]*3' "$LIFECYCLE"
    grep -Eq 'prefix[[:space:]]*=[[:space:]]*"uploads/"' "$LIFECYCLE"
}

@test "contains no completed lifecycle migration scaffolding" {
    run grep -Eq 'resource "minio_ilm_policy" "wanderbound_uploads"' "$LIFECYCLE"
    [ "$status" -eq 1 ]

    run grep -Eq '^(removed|import)[[:space:]]*\{' "$LIFECYCLE"
    [ "$status" -eq 1 ]
}

@test "ignores the unsupported Hetzner transition default field" {
    grep -Eq 'ignore_changes[[:space:]]*=[[:space:]]*\[transition_default_minimum_object_size\]' "$LIFECYCLE"
}
