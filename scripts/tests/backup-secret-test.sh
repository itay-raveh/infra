#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

secret=clusters/shire/apps/wanderbound/wanderbound-backup-secrets.sops.yaml
cronjob=clusters/shire/apps/wanderbound/data-backup.yaml

if ! grep -Fxq 'data:' "$secret"; then
    printf 'FAIL: the backup Secret must use the repository-wide Kubernetes data convention\n' >&2
    exit 1
fi

if grep -Fxq 'stringData:' "$secret"; then
    printf 'FAIL: stringData would encode the migrated base64 repository password a second time\n' >&2
    exit 1
fi

if ! grep -Fq 'name: wanderbound-backup-secrets' "$cronjob"; then
    printf 'FAIL: the backup CronJob must use the least-privilege backup-only Secret\n' >&2
    exit 1
fi

if ! grep -Eq 'restic backup /data --verbose --group-by paths' "$cronjob"; then
    printf 'FAIL: backups must ignore ephemeral Kubernetes Pod hostnames when selecting a parent\n' >&2
    exit 1
fi

grouping_count=$(grep -Fc -- '--group-by paths' "$cronjob")
if ! grep -Fq 'restic forget' "$cronjob" || (( grouping_count != 2 )); then
    printf 'FAIL: retention must use the same path grouping as backup parent selection\n' >&2
    exit 1
fi

printf 'backup Secret invariants passed\n'
