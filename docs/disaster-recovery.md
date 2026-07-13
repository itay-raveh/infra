# Disaster recovery

DR is not a separate procedure. The every-rebuild path in `setup.md`
is the DR path. Every time you rebuild shire for any reason, you're
drilling DR.

The node is cattle. All infrastructure rebuilds from git. Stateful
data lives in S3 backups (CNPG PITR, app-data tarballs, etcd
snapshots). Full recovery: rebuild from git + restore from S3.

---

## Single points of failure

| SPOF | Mitigation | If you lose it |
|---|---|---|
| **Tofu state bucket** (`shire-tfstate`) | Object Storage versioning. Quarterly `aws s3 sync` to a sibling bucket. | `tofu import` against live cloud resources. Painful afternoon. |
| **S3 backup bucket** (`shire-backups`) | Object Storage versioning + lifecycle rules. | Lose backup history. Running data unaffected. Re-create bucket and backups resume. |
| **Both YubiKeys** | Primary on keyring, backup offsite. Never travel with both. | **Permanent cryptographic loss.** Every `.sops.*` file becomes unrecoverable ciphertext. No recovery path - start over with new roots via `bootstrap/bootstrap.sh`. |
| **GitHub repo** | Monthly `git clone --mirror` to offline drive. | Source of truth gone. Same outcome as losing both YubiKeys if no mirror exists. |

Loss order: state bucket = painful afternoon. Repo = painful week.
Both YubiKeys = start from scratch.

---

## Restore procedures

When rebuilding after data loss, restore in this order: etcd first
(cluster state), then Postgres (application data), then app-data files
(uploads). Each section is self-contained.

### 1. etcd restore

Download the latest snapshot from S3 and bootstrap from it:

```
mc alias set hetzner https://fsn1.your-objectstorage.com ACCESS_KEY SECRET_KEY
mc ls hetzner/shire-backups/etcd/
mc cp hetzner/shire-backups/etcd/<latest>.snapshot ./db.snapshot
```

Snapshots are age-encrypted (public key in `talos-backup.yaml`).
Decrypt before restoring:

```
age --decrypt -i <(sops --decrypt bootstrap/cluster-age-key.sops.txt) \
  -o db.snapshot.dec db.snapshot
```

Then bootstrap the new node from the snapshot:

```
talosctl bootstrap --recover-from=./db.snapshot.dec
```

If the snapshot was copied raw from a crashed node rather than taken
via `talos-backup`, add `--recover-skip-hash-check`.

### 2. Postgres (CNPG PITR)

CNPG recovery always creates a **new** cluster. Apply a recovery
Cluster CR that references the Barman backup in S3:

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
      source: wanderbound-backup
      # recoveryTarget:
      #   targetTime: "2026-04-14T12:00:00Z"  # optional PITR
  plugins:
    - name: barman-cloud.cloudnative-pg.io
  externalClusters:
    - name: wanderbound-backup
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: wanderbound-backup
          serverName: wanderbound-db
```

Apply and watch the restore:

```
kubectl apply -f wanderbound-db-restore.yaml
kubectl -n wanderbound get cluster wanderbound-db-restore --watch
kubectl cnpg status -n wanderbound wanderbound-db-restore
```

After the restore cluster reports healthy, update `wanderbound-db.yaml`
to point at the restored data (rename the cluster or update secret
references), commit, and push.

### 3. App-data files

Download the latest tarball and pipe it into a temporary pod that
mounts the PVC:

```
mc cp hetzner/shire-backups/app-data/wanderbound/<latest>.tar.gz /tmp/

kubectl -n wanderbound run restore --rm -i \
  --image=alpine --restart=Never \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "restore",
        "image": "alpine",
        "command": ["sh", "-c", "tar xzf - -C /data"],
        "stdin": true,
        "volumeMounts": [{
          "name": "data",
          "mountPath": "/data"
        }]
      }],
      "volumes": [{
        "name": "data",
        "persistentVolumeClaim": {
          "claimName": "wanderbound-app-data"
        }
      }]
    }
  }' < /tmp/<latest>.tar.gz
```

### 4. App rollback

If a bad image was auto-deployed by Flux image automation:

```
# 1. Stop image automation from pushing more updates
flux suspend image update-automation wanderbound -n flux-system

# 2. Find the previous working digest
flux get image policy wanderbound-backend -n flux-system
kubectl -n wanderbound get deploy wanderbound-backend -o jsonpath='{.spec.template.spec.containers[0].image}'

# 3. Pin the deployment to the known-good digest
#    Edit the image tag in the deployment YAML, commit, push.
#    Flux will reconcile the pinned version.

# 4. After fixing the root cause, resume automation
flux resume image update-automation wanderbound -n flux-system
```

---

## WireGuard management is unavailable

First restore the workstation side from the encrypted source of truth:

```
mise run wireguard:configure
sudo wg show shire
```

If there is still no handshake, confirm that the Hetzner firewall has
the repository-managed UDP 51820 rule and that the server's stable
primary IP matches `mise run tofu:output -- public_ipv4`.

If the node lost its `WireguardConfig`, use this break-glass sequence:

1. In the Hetzner console, temporarily allow TCP 50000 to the server.
   Talos still requires its client certificate, so this exposes no
   password login or anonymous administration.
2. Run `mise run wireguard:recover`. It applies the repository's
   `WireguardConfig` through the public endpoint in try mode, activates
   the workstation peer, and makes the patch persistent only after the
   private Talos endpoint responds.
3. Remove the temporary TCP 50000 rule immediately. The steady-state
   firewall exposes only UDP 51820 for management.

Do not open TCP 6443 for this recovery. Once the Talos API is reachable
over WireGuard, Kubernetes is reachable through the same private route.

## One YubiKey lost

You are one hardware failure from total loss. Replace immediately:
buy a new YubiKey, generate keys on it, `sops updatekeys` every
`.sops.*` file, commit and push. See `age-plugin-yubikey` and `sops`
docs for the exact commands.
