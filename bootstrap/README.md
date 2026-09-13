# Bootstrap keys

Both files are encrypted to the YubiKeys listed in [.sops.yaml](../.sops.yaml).

| File | Purpose |
|---|---|
| `cluster-age-key.sops.txt` | Flux decryption key, installed as `flux-system/sops-age` by `mise run rebuild` |
| `etcd-backup-age-key.sops.txt` | Decrypts the Talos etcd snapshots in S3 |

[Key rotation](../docs/secrets.md) · [etcd recovery](../docs/disaster-recovery.md#restore-etcd)

## bootstrap.sh

[bootstrap.sh](bootstrap.sh) generates hardware keys and initial SOPS files,
configures Git signing, and replaces GitHub branch protection and rulesets.

The script needs repairs before a fresh setup: it omits the etcd backup key,
Flux GitHub App credentials and some provider credentials. For a replacement workstation,
use the [existing keys](../docs/setup.md#set-up-a-workstation).
