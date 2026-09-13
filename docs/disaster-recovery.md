# Disaster recovery

Choose the procedure for what was lost. Rebuilding infrastructure from Git
and restoring an etcd snapshot are different recovery paths.

| Failure | Start here |
|---|---|
| Workstation lost, cluster still running | [Restore workstation access](setup.md#set-up-a-workstation) |
| Management connection lost | [Recover WireGuard](#recover-wireguard-access) |
| Kubernetes control-plane data lost | [Restore etcd](#restore-etcd) |
| Database data lost or corrupted | [Restore PostgreSQL](#restore-postgresql) |
| Application files lost | [Recover files from restic](#recover-files-from-restic) |
| Bad application release | [Roll back the release](#roll-back-an-application-release) |
| Hardware key lost | [Replace the key](secrets.md#replace-a-hardware-key) |

## Backup inventory

| Data | Backup | Configuration |
|---|---|---|
| etcd | Every six hours, under `shire-backups/etcd/`; Zstandard compression followed by age encryption | [talos-backup.yaml](../clusters/shire/infrastructure/controllers/talos-backup.yaml) |
| Wanderbound PostgreSQL | Daily base backups and continuous WAL archiving under `shire-backups/cnpg/wanderbound/` | [ScheduledBackup](../clusters/shire/apps/wanderbound/wanderbound-db-scheduled-backup.yaml), [ObjectStore](../clusters/shire/apps/wanderbound/objectstore.yaml) |
| Wanderbound PVC files | Daily restic snapshots under `shire-backups/app-data/wanderbound`; retains seven daily, four weekly and three monthly snapshots | [data-backup.yaml](../clusters/shire/apps/wanderbound/data-backup.yaml) |

Bucket versioning and expiration rules are in [tofu/backups.tf](../tofu/backups.tf).
Check actual backup timestamps and job results before a destructive operation;
a configured schedule does not establish that a usable backup exists.
Wanderbound's separate uploads bucket is configured in
[wanderbound_uploads.tf](../tofu/wanderbound_uploads.tf) and is outside the PVC backup.

Recovery also requires the encrypted repository files, a usable hardware key,
and the OpenTofu state at `shire-tfstate/shire/terraform.tfstate`.
This repository does not configure an independent mirror of that state bucket
or the Git repository. Losing state can also lose generated Talos credentials;
importing cloud resources does not reconstruct those secrets.

## Restore etcd

Use this path to recover Kubernetes control-plane state. It does not recover
the contents of application volumes or PostgreSQL.

1. Obtain a snapshot from `shire-backups/etcd/`. The commands below assume
   `mc` already has a `hetzner` alias authenticated to the Object Storage
   endpoint in [backend.tf](../tofu/backend.tf). Install `zstd` locally as well;
   it is not included in the repository's mise tools.
2. List the objects and substitute the chosen relative object path for
   `<SNAPSHOT_OBJECT>`. Keep the decrypted snapshot outside the checkout:

   ```bash
   set -o pipefail
   snapshot_dir=$(mktemp -d)
   mc ls --recursive hetzner/shire-backups/etcd/
   mc cp 'hetzner/shire-backups/etcd/<SNAPSHOT_OBJECT>' "$snapshot_dir/snapshot.age"
   age --decrypt \
     -i <(sops decrypt bootstrap/etcd-backup-age-key.sops.txt) \
     "$snapshot_dir/snapshot.age" \
     | zstd --decompress > "$snapshot_dir/db.snapshot"
   ```

   Continue only if download, decryption and decompression succeed. The key is
   the dedicated etcd backup key, not `cluster-age-key.sops.txt`. The backup
   format is defined by [talos-backup](https://github.com/siderolabs/talos-backup).
3. Follow the [Talos recovery procedure](https://docs.siderolabs.com/talos/v1.12/build-and-extend-talos/cluster-operations-and-maintenance/disaster-recovery)
   to prepare the control plane using its original machine secrets. Stop before
   any reset if the snapshot or credentials are unavailable. **Do not run
   `mise run rebuild` first:** it performs normal cluster bootstrap.
4. When the target control plane's etcd service is in `Preparing`, restore:

   ```bash
   talosctl service etcd
   talosctl bootstrap --recover-from="$snapshot_dir/db.snapshot"
   talosctl etcd status
   kubectl get nodes
   ```

Keep snapshot integrity checking enabled for backups from the CronJob. Talos's
skip-hash option is for a raw database copied from a failed node, not a way to
ignore a damaged regular snapshot. After recovery, verify Flux readiness and
application data before removing local snapshot files.

## Restore PostgreSQL

The Barman plugin restores into a new CNPG cluster. The example below reads
Wanderbound's existing backup archive and leaves the original cluster in place.
The CNPG operator, Barman plugin, `wanderbound-backup` ObjectStore and
`cnpg-s3-creds` Secret must exist in the `wanderbound` namespace.

Save this as a recovery manifest outside the checkout:

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

For recovery to a particular time, add `bootstrap.recovery.recoveryTarget`
before creating the cluster. Check the target against the available base
backups and WAL. The [Barman plugin recovery reference](https://cloudnative-pg.io/plugin-barman-cloud/docs/concepts/)
explains the source fields; [CNPG recovery](https://cloudnative-pg.io/docs/current/recovery/)
describes recovery targets.

```bash
kubectl apply -f '<RECOVERY_MANIFEST>'
kubectl -n wanderbound get cluster wanderbound-db-restore --watch
kubectl cnpg status -n wanderbound wanderbound-db-restore
kubectl cnpg psql -n wanderbound wanderbound-db-restore -- wanderbound
```

Check the restored schema and data before changing application connections.
Cutover also needs working application credentials: the current HelmRelease
reads `SQLALCHEMY_DATABASE_URI` from `wanderbound-db-app`. Update that reference
and any required role credentials through the deployment workflow. Configure
backups for the restored cluster before retiring the original. Do not point
a second WAL writer at the original cluster's archive.

## Recover files from restic

Wanderbound backs up PVC files with restic. Use a local
[restic installation](https://restic.readthedocs.io/en/stable/020_installation.html)
matching the version in [data-backup.yaml](../clusters/shire/apps/wanderbound/data-backup.yaml).
Choose a destination with space for the restored files.

Run this Bash block from the repository root. It reads the existing encrypted
credentials, lets you choose a snapshot, and restores into a new local directory:

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
  printf 'Restored files: %s/data
' "$restore_dir"
)
```

The snapshot contains `/data`, so files appear under the destination's `data/`
directory. Check the restore result and required files before a volume cutover.
See [restic restore](https://restic.readthedocs.io/en/stable/050_restore.html).

This procedure recovers files to the workstation. Replacing the live PVC
contents requires stopping application writes and backup jobs, transferring
the recovered files while preserving ownership, and verifying the application
before resuming backups. There is no repository task for that cutover.

## Roll back an application release

For an unwanted Wanderbound chart update:

1. Suspend new automated updates and inspect any pending PR from
   `flux-image-automation`:

   ```bash
   flux suspend image update-automation wanderbound -n flux-system
   ```

2. Find the known-good chart version in Git history:

   ```bash
   git log -p -- clusters/shire/apps/wanderbound/app-chart.yaml
   ```

3. Restore that version in `app-chart.yaml`, review and merge the change, then
   reconcile Flux. Verify the deployed application and any database migration
   compatibility before resuming automation:

   ```bash
   flux resume image update-automation wanderbound -n flux-system
   ```

## Recover WireGuard access

First restore the workstation configuration:

```bash
mise run wireguard:configure
sudo wg show shire
mise run tofu:output -- public_ipv4
```

If there is no handshake, compare the endpoint with the stable IP and check
the Hetzner UDP 51820 rule. If the node has lost its WireGuard configuration:

1. Temporarily allow TCP 50000 from the operator's public IP in the Hetzner
   firewall. Keep the existing Talos client credentials available.
2. Run `mise run wireguard:recover`. It applies the WireGuard patch through
   the public Talos endpoint in try mode and makes it persistent only after
   the private endpoint responds.
3. Remove the temporary firewall rule. Confirm private access with
   `talosctl health` and `kubectl get nodes`.

The [recovery script](../scripts/recover-wireguard.sh) does not need public
access to Kubernetes port 6443. If private verification fails, the temporary
Talos configuration rolls back automatically.
