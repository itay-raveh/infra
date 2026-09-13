# Bootstrap artifacts

This directory holds the software age keys needed to initialize Flux and
recover etcd backups. Both files are encrypted to the hardware recipients
in [.sops.yaml](../.sops.yaml).

| File | Used by |
|---|---|
| `cluster-age-key.sops.txt` | `mise run rebuild`, which installs the key in the `flux-system/sops-age` Secret so Flux can decrypt cluster manifests |
| `etcd-backup-age-key.sops.txt` | Operators decrypting snapshots written by the Talos backup job |

These keys are independent. The Flux key cannot decrypt etcd backups.
See [secrets](../docs/secrets.md) for recipients and rotation, and
[disaster recovery](../docs/disaster-recovery.md#restore-etcd) for snapshot recovery.

## Initial provisioning script

[bootstrap.sh](bootstrap.sh) creates hardware keys, configures Git signing,
registers signing keys with GitHub, writes initial SOPS files, and replaces
GitHub branch protection and repository rulesets. It refuses to run when its
initial output files already exist.

The script does not provision a complete copy of the current environment.
It does not create the dedicated etcd backup key, Flux GitHub App credentials,
or all credentials now required by the OpenTofu configuration. Its initial
SOPS encryption also uses a temporary filename that does not match the
creation rule for `tofu/secrets.sops.yaml`.

Do not use this script to prepare a replacement workstation or rotate keys.
Use [workstation setup](../docs/setup.md#set-up-a-workstation) with the existing
keys and encrypted files. A new environment requires updating and validating
the script against the current configuration first.
