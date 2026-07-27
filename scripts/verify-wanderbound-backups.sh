#!/usr/bin/env bash
set -euo pipefail

namespace=wanderbound
restore_suffix="$(date +%s)-$$"
database_restore="wanderbound-db-restore-$restore_suffix"
data_restore="wanderbound-data-restore-$restore_suffix"

cleanup() {
    kubectl --namespace "$namespace" delete job "$data_restore" \
        --ignore-not-found --wait=false >/dev/null
    kubectl --namespace "$namespace" delete cluster "$database_restore" \
        --ignore-not-found --wait=false >/dev/null
    kubectl --namespace "$namespace" delete pvc "$data_restore" \
        --ignore-not-found --wait=false >/dev/null
    kubectl --namespace "$namespace" delete pvc \
        --selector="cnpg.io/cluster=$database_restore" \
        --ignore-not-found --wait=false >/dev/null
}
trap cleanup EXIT

kubectl --namespace "$namespace" apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $database_restore
spec:
  instances: 1
  bootstrap:
    recovery:
      source: wanderbound-backup-source
      database: wanderbound
      owner: app
  externalClusters:
    - name: wanderbound-backup-source
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: wanderbound-backup
          serverName: wanderbound-db
  storage:
    size: 5Gi
    storageClass: hcloud-volumes
  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: "1"
EOF

kubectl --namespace "$namespace" wait \
    --for=condition=ready "cluster/$database_restore" --timeout=20m
schema_present=$(kubectl cnpg psql --namespace "$namespace" "$database_restore" \
    -- wanderbound -tAc "SELECT to_regclass('public.alembic_version') IS NOT NULL" \
    | tr -d '[:space:]')
if [[ "$schema_present" != t ]]; then
    printf 'restored database is missing the application schema\n' >&2
    exit 1
fi

kubectl --namespace "$namespace" apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $data_restore
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: hcloud-volumes
  resources:
    requests:
      storage: 50Gi
---
apiVersion: batch/v1
kind: Job
metadata:
  name: $data_restore
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      securityContext:
        fsGroup: 1000
      containers:
        - name: restore
          image: restic/restic:0.19.1@sha256:08916bcda4a4435f9d9828ebb4e91bb7ada3d2c8a53699788930e0ae1bd4fa67
          command: [/bin/sh, -ec]
          args:
            - restic restore latest --target /restore && test -d /restore/data
          env:
            - name: RESTIC_REPOSITORY
              value: s3:https://fsn1.your-objectstorage.com/shire-backups/app-data/wanderbound
            - name: RESTIC_CACHE_DIR
              value: /tmp/cache
            - name: RESTIC_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: wanderbound-backup-secrets
                  key: RESTIC_PASSWORD
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: cnpg-s3-creds
                  key: ACCESS_KEY_ID
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: cnpg-s3-creds
                  key: ACCESS_SECRET_KEY
          volumeMounts:
            - name: restore
              mountPath: /restore
            - name: tmp
              mountPath: /tmp
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            readOnlyRootFilesystem: true
            seccompProfile:
              type: RuntimeDefault
      volumes:
        - name: restore
          persistentVolumeClaim:
            claimName: $data_restore
        - name: tmp
          emptyDir: {}
EOF

if ! kubectl --namespace "$namespace" wait \
    --for=condition=complete "job/$data_restore" --timeout=30m; then
    kubectl --namespace "$namespace" logs "job/$data_restore" || true
    exit 1
fi
kubectl --namespace "$namespace" logs "job/$data_restore"

printf 'Wanderbound database and app-data restores verified.\n'
