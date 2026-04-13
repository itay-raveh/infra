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
| **Tofu state bucket** (`raveh-infra-tfstate`) | Object Storage versioning. Quarterly `aws s3 sync` to a sibling bucket. | `tofu import` against live cloud resources. Painful afternoon. |
| **S3 backup bucket** (`shire-backups`) | Object Storage versioning + lifecycle rules. | Lose backup history. Running data unaffected. Re-create bucket and backups resume. |
| **Both YubiKeys** | Primary on keyring, backup offsite. Never travel with both. | **Permanent cryptographic loss.** Every `.sops.*` file becomes unrecoverable ciphertext. No recovery path - start over with new roots via `bootstrap/bootstrap.sh`. |
| **GitHub repo** | Monthly `git clone --mirror` to offline drive. | Source of truth gone. Same outcome as losing both YubiKeys if no mirror exists. |

Loss order: state bucket = painful afternoon. Repo = painful week.
Both YubiKeys = start from scratch.

---

## S3 restore paths

When rebuilding after data loss, restore in this order:

1. **etcd**: `talosctl bootstrap --recover-from=./db.snapshot` using
   latest snapshot from `s3://shire-backups/etcd/`
2. **Postgres**: CNPG point-in-time restore (create new Cluster CR
   bootstrapped from Barman backup)
3. **App data**: download latest tarball from
   `s3://shire-backups/app-data/wanderbound/`, extract into PVC

---

## One YubiKey lost

You are one hardware failure from total loss. Replace immediately:
buy a new YubiKey, generate keys on it, `sops updatekeys` every
`.sops.*` file, commit and push. See `age-plugin-yubikey` and `sops`
docs for the exact commands.
