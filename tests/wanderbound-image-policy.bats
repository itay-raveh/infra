#!/usr/bin/env bats

setup() {
    load test_helper/common
    setup_repo
    POLICY=clusters/shire/apps/wanderbound/image-automation.yaml
}

@test "Wanderbound image policies select immutable stable releases" {
    for name in wanderbound-frontend wanderbound-backend; do
        NAME="$name" run yq -e '
            select(.kind == "ImagePolicy" and .metadata.name == strenv(NAME)) |
            .spec.filterTags.pattern == "^v(?P<version>(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*))$" and
            .spec.filterTags.extract == ("$" + "version") and
            .spec.policy.semver.range == ">=1.0.0" and
            .spec.digestReflectionPolicy == "IfNotPresent" and
            .spec.interval == null
        ' "$POLICY"
        [ "$status" -eq 0 ]
    done
}
