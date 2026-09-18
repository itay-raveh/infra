#!/usr/bin/env bash
set -euo pipefail

# Refuse the operator's context if this helper is invoked directly.
[[ $(kubectl config current-context) == kind-infra-test-* ]]
fixture=tests/integration/database.yaml
kubectl -n fixture create secret generic cnpg-s3-creds \
  --from-literal=ACCESS_KEY_ID=fixture-access --from-literal=ACCESS_SECRET_KEY=fixture-secret
kubectl apply -f "$fixture"
kubectl -n fixture wait cluster/database --for=condition=Ready --timeout=300s
kubectl -n fixture exec database-1 -c postgres -- \
  psql -U postgres -d app -v ON_ERROR_STOP=1 -c \
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
    name: database
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
YAML
kubectl -n fixture wait backup/fixture --for=jsonpath='{.status.phase}'=completed --timeout=300s
yq 'select(.kind == "Cluster") | .metadata.name = "restored" | del(.spec.plugins) |
  .spec.bootstrap = {"recovery": {"source": "origin"}} |
  .spec.externalClusters = [{"name": "origin", "plugin": {
    "name": "barman-cloud.cloudnative-pg.io", "parameters": {
      "barmanObjectName": "backup", "serverName": "database"
    }}}]' "$fixture" | kubectl apply -f -
kubectl -n fixture wait cluster/restored --for=condition=Ready --timeout=300s
[[ $(kubectl -n fixture exec restored-1 -c postgres -- \
  psql -U postgres -d app -Atc 'SELECT value FROM recovery_fixture WHERE id = 1') == 'survives restore' ]]
printf 'CNPG/Barman backup and restore passed.\n'

image=restic/restic:0.19.1@sha256:08916bcda4a4435f9d9828ebb4e91bb7ada3d2c8a53699788930e0ae1bd4fa67
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
kubectl -n fixture exec restic -- restic backup /data --group-by paths
kubectl -n fixture exec restic -- restic forget --group-by paths --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
# The assertion runs inside the test pod.
# shellcheck disable=SC2016
kubectl -n fixture exec restic -- sh -eu -c '
  rm /data/original.txt
  restic restore latest --target /restored
  restic check --read-data
  test "$(cat /restored/data/original.txt)" = "file recovery fixture"
'
printf 'Restic backup, retention command and restore passed.\n'
