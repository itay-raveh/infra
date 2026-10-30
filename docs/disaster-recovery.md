# Recovery

## Backup locations

| Data | Configuration | Storage |
|---|---|---|
| etcd | [talos-backup.yaml](../clusters/shire/infrastructure/controllers/talos-backup.yaml) | `shire-backups/etcd/`, age-encrypted snapshots |
| PostgreSQL | Application `ObjectStore` and `ScheduledBackup` resources | Per-cluster prefix in `shire-backups/cnpg/` |
| Persistent files | Application backup CronJob | Its `RESTIC_REPOSITORY` |

Schedules and retention live in those manifests. [Bucket lifecycle rules](../tofu/backups.tf) preserve current CNPG objects for Barman to manage. Upload buckets may be separate from volume backups.

Recovery requires the encrypted repository, a YubiKey and OpenTofu state. Keep independent copies of state, backups and Git; this repo does not schedule offsite copies. Bucket versioning does not protect against bucket deletion. See [key recovery](secrets.md#rotation).

## Restore etcd

Install `zstd`. Load the read-only recovery credential from SOPS and choose a snapshot:

```bash
bash scripts/sops-exec.sh secrets/backup-recovery.sops.yaml -- mc ls --recursive hetzner/shire-backups/etcd/
set -o pipefail
umask 077
snapshot_dir=$(mktemp -d)
bash scripts/sops-exec.sh secrets/backup-recovery.sops.yaml -- mc cp 'hetzner/shire-backups/etcd/<SNAPSHOT_OBJECT>' "$snapshot_dir/snapshot.age"
age --decrypt -i <(sops decrypt bootstrap/etcd-backup-age-key.sops.txt) "$snapshot_dir/snapshot.age" | zstd --decompress > "$snapshot_dir/db.snapshot"
```

Follow [Talos recovery](https://docs.siderolabs.com/talos/v1.14/build-and-extend-talos/cluster-operations-and-maintenance/disaster-recovery) using the original machine credentials. Do not run `rebuild`, which creates an empty cluster. Once etcd reports `Preparing`:

```bash
talosctl bootstrap --recover-from="$snapshot_dir/db.snapshot"
talosctl etcd status
kubectl get nodes
flux get kustomizations -A
```

Remove the plaintext snapshot after verification. Database and file contents require separate restores.

## Restore PostgreSQL

Keep the source `ObjectStore` and its credential Secret available. Create a new CNPG cluster using the backup's PostgreSQL major version and archive server name:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <RESTORE_CLUSTER>
  namespace: <NAMESPACE>
spec:
  imageName: <POSTGRES_IMAGE_MATCHING_BACKUP>
  instances: 1
  storage:
    size: <RESTORE_SIZE>
  bootstrap:
    recovery:
      source: original
  externalClusters:
    - name: original
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: <OBJECT_STORE>
          serverName: <SOURCE_CLUSTER>
```

For PITR, set `bootstrap.recovery.recoveryTarget` before creation. [Recovery targets](https://cloudnative-pg.io/docs/current/recovery/) and [Barman fields](https://cloudnative-pg.io/plugin-barman-cloud/docs/concepts/).

```bash
kubectl apply -f '<RECOVERY_MANIFEST>'
kubectl cnpg status -n '<NAMESPACE>' '<RESTORE_CLUSTER>'
kubectl cnpg psql -n '<NAMESPACE>' '<RESTORE_CLUSTER>' -- '<DATABASE>'
```

Inspect recovered data before updating application connection references. Configure the restored roles' credentials and TLS. Use a distinct backup server name before enabling WAL archiving on the restored cluster.

## Restore files

Read `RESTIC_REPOSITORY`, `RESTIC_PASSWORD` and S3 credentials from the selected backup job's configuration and Secret references. Export them in a private shell; use the job's restic version.

```bash
restic snapshots
restic ls '<SNAPSHOT_ID>'
restic restore '<SNAPSHOT_ID>' --target '<NEW_DIRECTORY>' --verify
```

Stop application writes and the backup job before copying restored files to the volume, preserving ownership. Run `restic init` only for a new, empty repository; it does not repair access errors.

## Recover WireGuard access

```bash
mise run wireguard:configure
sudo wg show shire
mise run tofu:output -- public_ipv4
```

If the server-side tunnel configuration is missing:

1. Temporarily permit TCP 50000 from the workstation's public IP in Hetzner.
2. Run `mise run wireguard:recover` with the existing Talos credentials.
3. Verify `talosctl health` and `kubectl get nodes` over WireGuard, then remove the temporary rule.

The script persists its patch only after the private endpoint responds; failed attempts roll it back. Public Kubernetes access on port 6443 is unnecessary.
