#!/usr/bin/env bats

load test_helper/common

setup() {
    setup_repo
    SECRET=clusters/shire/apps/wanderbound/wanderbound-backup-secrets.sops.yaml
    CRONJOB=clusters/shire/apps/wanderbound/data-backup.yaml
}

@test "stores the repository password under data without stringData" {
    run yq -e '.data.RESTIC_PASSWORD != null and .stringData == null' "$SECRET"

    [ "$status" -eq 0 ]
}

@test "injects the password from the backup-only secret" {
    run yq -e '.spec.jobTemplate.spec.template.spec.containers[] | select(.name == "backup") | .env[] | select(.name == "RESTIC_PASSWORD") | .valueFrom.secretKeyRef.name == "wanderbound-backup-secrets"' "$CRONJOB"

    [ "$status" -eq 0 ]
}

@test "groups backup parent selection and retention by path" {
    command=$(yq -r '.spec.jobTemplate.spec.template.spec.containers[] | select(.name == "backup") | .command[2]' "$CRONJOB")

    [[ "$command" == *"restic backup /data --verbose --group-by paths"* ]]
    [[ "$command" == *"restic forget"* ]]
    [ "$(grep -oF -- '--group-by paths' <<<"$command" | wc -l)" -eq 2 ]
}
