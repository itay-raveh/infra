# Recovery

| Backup | Location in `shire-backups` | Schedule and retention |
|---|---|---|
| [etcd](../clusters/shire/infrastructure/controllers/talos-backup.yaml) | `etcd/` | Every six hours; age-encrypted Zstandard snapshots |
| [PostgreSQL](../clusters/shire/apps/wanderbound/objectstore.yaml) | `cnpg/wanderbound/` | Daily base backups, continuous WAL; 30-day recovery window |
| [Wanderbound files](../clusters/shire/apps/wanderbound/data-backup.yaml) | `app-data/wanderbound` | Daily restic snapshots; seven daily, four weekly, three monthly |

[Bucket rules](../tofu/backups.tf) expire noncurrent CNPG objects after 60 days
and etcd snapshots after seven. Barman retains the pre-window base backup and
required WAL. The [uploads bucket](../tofu/wanderbound_uploads.tf) is outside
the PVC backup.

Cluster recovery also needs the encrypted repo files, a YubiKey, and OpenTofu
state at `shire-tfstate/shire/terraform.tfstate`, which holds the Talos credentials.

## Recovery dependencies

| Dependency lost | Recovery |
|---|---|
| OpenTofu state bucket | Restore an independent state copy or import surviving cloud resources. Importing does not reconstruct generated Talos credentials. The backend bucket is an [account prerequisite](setup.md#account-prerequisites), managed outside this configuration. |
| Backup bucket | Recover from another backup copy or the running data. Bucket versioning cannot recover a deleted bucket. |
| GitHub repository | Recover from a local clone or offline mirror, including encrypted files and history. Re-create repository access and settings before resuming Flux. |
| One or both YubiKeys | See [key-loss limits](secrets.md#protection-and-limits) and [key replacement](secrets.md#replace-a-hardware-key). |

Keep independent state, backup and Git copies and an offsite YubiKey. This repo
does not schedule external copies; bucket versioning stays within Hetzner.

## Restore etcd

Install `zstd` and configure an authenticated `mc` alias named `hetzner` for
`https://fsn1.your-objectstorage.com`. Select a snapshot:

```bash
mc ls --recursive hetzner/shire-backups/etcd/
```

Replace `<SNAPSHOT_OBJECT>` with its path under `etcd/`:

```bash
set -o pipefail
umask 077
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

This restores Kubernetes state. Restore databases and files separately below,
then remove the plaintext snapshot.

## Restore PostgreSQL

Requires the CNPG operator, Barman plugin, `wanderbound-backup` ObjectStore and
`cnpg-s3-creds` Secret. Create a new cluster from the existing archive. Replace
`<POSTGRES_IMAGE_MATCHING_BACKUP>` with an image using the backup's PostgreSQL
major version:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: wanderbound-db-restore
  namespace: wanderbound
spec:
  imageName: <POSTGRES_IMAGE_MATCHING_BACKUP>
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
at the [backup job's version](../clusters/shire/apps/wanderbound/data-backup.yaml).
Restore a snapshot into a new workstation directory:

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

### Initialize an empty restic repository

For a new, empty repository, run `restic init` once using the backup job's
credentials. Do not run this to repair authentication or network failures:

```bash
set -o pipefail
kubectl -n wanderbound create job restic-init \
  --from=cronjob/wanderbound-data-backup --dry-run=client -o yaml |
  yq '.spec.template.spec.containers[0].command = ["restic", "init"]' |
  kubectl apply -f -
kubectl -n wanderbound wait --for=condition=complete job/restic-init --timeout=5m &&
  kubectl -n wanderbound delete job restic-init
```

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
