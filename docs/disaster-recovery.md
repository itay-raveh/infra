# Recovery

| Backup | Location in `shire-backups` | Schedule and retention |
|---|---|---|
| [etcd](../clusters/shire/infrastructure/controllers/talos-backup.yaml) | `etcd/` | Every six hours; age-encrypted Zstandard snapshots |
| [PostgreSQL](../clusters/shire/apps/wanderbound/objectstore.yaml) | `cnpg/wanderbound/` | Daily base backups, continuous WAL; 30-day retention |
| [Wanderbound files](../clusters/shire/apps/wanderbound/data-backup.yaml) | `app-data/wanderbound` | Daily restic snapshots; seven daily, four weekly, three monthly |

Bucket expiration rules are in [backups.tf](../tofu/backups.tf). The separate
[uploads bucket](../tofu/wanderbound_uploads.tf) is outside the PVC backup.

Cluster recovery also needs the encrypted repo files, a YubiKey, and OpenTofu
state at `shire-tfstate/shire/terraform.tfstate`, which holds the Talos credentials.

## Restore etcd

Install `zstd` and configure an authenticated `mc` alias named `hetzner` for
`https://fsn1.your-objectstorage.com`. Select a snapshot:

```bash
mc ls --recursive hetzner/shire-backups/etcd/
```

Replace `<SNAPSHOT_OBJECT>` with its path under `etcd/`:

```bash
set -o pipefail
snapshot_dir=$(mktemp -d)
mc cp 'hetzner/shire-backups/etcd/<SNAPSHOT_OBJECT>' "$snapshot_dir/snapshot.age"
age --decrypt \
  -i <(sops decrypt bootstrap/etcd-backup-age-key.sops.txt) \
  "$snapshot_dir/snapshot.age" \
  | zstd --decompress > "$snapshot_dir/db.snapshot"
```

Finish decryption before resetting the node. Prepare the control plane with
its original machine credentials using the [Talos recovery procedure](https://docs.siderolabs.com/talos/v1.12/build-and-extend-talos/cluster-operations-and-maintenance/disaster-recovery).
Do not run `mise run rebuild`: it bootstraps an empty cluster.

Once `talosctl service etcd` reports `Preparing`:

```bash
talosctl bootstrap --recover-from="$snapshot_dir/db.snapshot"
talosctl etcd status
kubectl get nodes
flux get kustomizations -A
```

The backup restores Kubernetes state. PostgreSQL and volume contents have
separate backups, described below.

## Restore PostgreSQL

Requires the CNPG operator, Barman plugin, `wanderbound-backup` ObjectStore and
`cnpg-s3-creds` Secret. Create a new cluster from the existing archive:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: wanderbound-db-restore
  namespace: wanderbound
spec:
  instances: 1
  storage:
    size: 5Gi
  bootstrap:
    recovery:
      source: original
  externalClusters:
    - name: original
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: wanderbound-backup
          serverName: wanderbound-db
```

For point-in-time recovery, set `bootstrap.recovery.recoveryTarget` before
creating the cluster. See [CNPG recovery targets](https://cloudnative-pg.io/docs/current/recovery/)
and the [Barman source fields](https://cloudnative-pg.io/plugin-barman-cloud/docs/concepts/).

```bash
kubectl apply -f '<RECOVERY_MANIFEST>'
kubectl cnpg status -n wanderbound wanderbound-db-restore
kubectl cnpg psql -n wanderbound wanderbound-db-restore -- wanderbound
```

Inspect the recovered data before switching the application. Its HelmRelease
currently reads `SQLALCHEMY_DATABASE_URI` from `wanderbound-db-app`; cutover
requires updating that reference and configuring the restored role's credentials.
Use a distinct backup server name before enabling WAL archiving on the restored cluster.

## Recover files from restic

Install [restic](https://restic.readthedocs.io/en/stable/020_installation.html)
at the version in [data-backup.yaml](../clusters/shire/apps/wanderbound/data-backup.yaml).
This restores a selected snapshot to a new directory on the workstation:

```bash
(
  set -euo pipefail
  umask 077
  export RESTIC_REPOSITORY=s3:https://fsn1.your-objectstorage.com/shire-backups/app-data/wanderbound
  AWS_ACCESS_KEY_ID=$(sops decrypt --extract '["data"]["ACCESS_KEY_ID"]' \
    clusters/shire/apps/wanderbound/cnpg-s3-creds.sops.yaml | base64 --decode)
  AWS_SECRET_ACCESS_KEY=$(sops decrypt --extract '["data"]["ACCESS_SECRET_KEY"]' \
    clusters/shire/apps/wanderbound/cnpg-s3-creds.sops.yaml | base64 --decode)
  RESTIC_PASSWORD=$(sops decrypt --extract '["data"]["RESTIC_PASSWORD"]' \
    clusters/shire/apps/wanderbound/wanderbound-backup-secrets.sops.yaml | base64 --decode)
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD
  restic snapshots
  read -r -p 'Snapshot ID: ' snapshot_id
  test -n "$snapshot_id"
  restic ls "$snapshot_id"
  read -r -p 'Parent directory for restored files: ' restore_parent
  test -d "$restore_parent"
  restore_dir=$(mktemp -d "$restore_parent/wanderbound-restore.XXXXXX")
  restic restore "$snapshot_id" --target "$restore_dir" --verify
  printf 'Restored files: %s/data\n' "$restore_dir"
)
```

Files appear under `<restore_dir>/data/`. Stop application writes and the
backup CronJob before copying them to the PVC, preserving file ownership.
The repo has no automated PVC cutover task.

## Roll back an application release

Pause Wanderbound updates and find the last working chart version:

```bash
flux suspend image update-automation wanderbound -n flux-system
git log -p -- clusters/shire/apps/wanderbound/app-chart.yaml
```

A pending PR from `flux-image-automation` can still merge while the controller
is paused. Check it before changing the version in `app-chart.yaml`.
Merge the rollback and run `mise run reconcile`. Chart rollback does not undo
database migrations.

Resume updates after fixing the release:

```bash
flux resume image update-automation wanderbound -n flux-system
```

## Recover WireGuard access

Restore the workstation peer and compare its endpoint with the server IP:

```bash
mise run wireguard:configure
sudo wg show shire
mise run tofu:output -- public_ipv4
```

If UDP 51820 is allowed and the node's WireGuard configuration is missing:

1. Temporarily allow TCP 50000 from the workstation's public IP in Hetzner.
2. Run `mise run wireguard:recover` with the existing Talos client credentials.
3. Remove the temporary firewall rule after `talosctl health` and
   `kubectl get nodes` work over WireGuard.

The [script](../scripts/recover-wireguard.sh) persists the patch only after
the private endpoint responds. A failed attempt rolls back the Talos patch.
Public access to Kubernetes port 6443 is unnecessary.
