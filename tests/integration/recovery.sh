#!/usr/bin/env bash
set -euo pipefail

# Refuse the operator's context if this helper is invoked directly.
[[ $(kubectl config current-context) == kind-infra-test-* ]]
source_dir=clusters/shire/apps/wanderbound
kubectl -n fixture create secret generic cnpg-s3-creds \
  --from-literal=ACCESS_KEY_ID=fixture-access --from-literal=ACCESS_SECRET_KEY=fixture-secret
yq '.metadata.namespace = "fixture" |
  .spec.configuration.endpointURL = "http://minio.fixture.svc.cluster.local:9000" |
  .spec.configuration.destinationPath = "s3://backups/cnpg/"' "$source_dir/objectstore.yaml" | kubectl apply -f -
yq '.metadata.namespace = "fixture" | .spec.storage.size = "1Gi"' \
  "$source_dir/wanderbound-db.yaml" | kubectl apply -f -
kubectl -n fixture wait cluster/wanderbound-db --for=condition=Ready --timeout=300s
kubectl -n fixture exec wanderbound-db-1 -c postgres -- \
  psql -U postgres -d wanderbound -v ON_ERROR_STOP=1 -c \
  "CREATE TABLE recovery_fixture (id integer PRIMARY KEY, value text); INSERT INTO recovery_fixture VALUES (1, 'survives restore');"
cat <<'YAML' | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: fixture
  namespace: fixture
spec:
  method: plugin
  cluster:
    name: wanderbound-db
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
YAML
kubectl -n fixture wait backup/fixture --for=jsonpath='{.status.phase}'=completed --timeout=300s
yq '.metadata.name = "restored" | .metadata.namespace = "fixture" |
  .spec.storage.size = "1Gi" | del(.spec.plugins) |
  .spec.bootstrap = {"recovery": {"source": "origin"}} |
  .spec.externalClusters = [{"name": "origin", "plugin": {
    "name": "barman-cloud.cloudnative-pg.io", "parameters": {
      "barmanObjectName": "wanderbound-backup", "serverName": "wanderbound-db"
    }}}]' "$source_dir/wanderbound-db.yaml" | kubectl apply -f -
kubectl -n fixture wait cluster/restored --for=condition=Ready --timeout=300s
[[ $(kubectl -n fixture exec restored-1 -c postgres -- \
  psql -U postgres -d wanderbound -Atc 'SELECT value FROM recovery_fixture WHERE id = 1') == 'survives restore' ]]
printf 'CNPG/Barman backup and restore passed.\n'

image=$(yq '.spec.jobTemplate.spec.template.spec.containers[0].image' "$source_dir/data-backup.yaml")
kubectl -n fixture run restic --image="$image" \
  --env=RESTIC_REPOSITORY=s3:http://minio.fixture.svc.cluster.local:9000/backups/app-data \
  --env=RESTIC_PASSWORD="$(openssl rand -hex 32)" --env=AWS_ACCESS_KEY_ID=fixture-access \
  --env=AWS_SECRET_ACCESS_KEY=fixture-secret --command -- sleep 600
kubectl -n fixture wait pod/restic --for=condition=Ready --timeout=180s
kubectl -n fixture exec restic -- sh -eu -c '
  mkdir /data
  printf "file recovery fixture\n" > /data/original.txt
  restic init
'
backup_command=$(yq '.spec.jobTemplate.spec.template.spec.containers[0].command[2]' "$source_dir/data-backup.yaml")
kubectl -n fixture exec restic -- sh -eu -c "$backup_command"
# The assertion runs inside the test pod.
# shellcheck disable=SC2016
kubectl -n fixture exec restic -- sh -eu -c '
  rm /data/original.txt
  restic restore latest --target /restored
  restic check --read-data
  test "$(cat /restored/data/original.txt)" = "file recovery fixture"
'
printf 'Restic backup, retention command and restore passed.\n'
