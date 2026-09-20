# Secrets

## Storage

[.sops.yaml](../.sops.yaml) selects recipients by path.

| Path | Contents | Decryption |
|---|---|---|
| `secrets/state.sops.yaml` | S3 state access and encryption passphrase | Either YubiKey |
| `secrets/tofu.sops.yaml` | Provider credentials and account identifiers | Either YubiKey |
| `secrets/wireguard.sops.yaml` | Server private key and workstation public key | Either YubiKey |
| `secrets/workstation.sops.yaml` | Workstation private key | Either YubiKey |
| `bootstrap/*.sops.txt` | Flux and etcd private keys | Either YubiKey |
| `clusters/**/*.sops.*` | Kubernetes Secrets, beside their consumers | Either YubiKey or Flux age key |

Flux uses `flux-system/sops-age`. OpenTofu encrypts state and plans through [backend.tf](../tofu/backend.tf). Local client configs and credentials inside running processes remain plaintext.

### Trust roots

[Bootstrap](../bootstrap/bootstrap.sh) creates independent PIV age and resident SSH signing keys on two YubiKeys. Its age policy requires touch but no PIN. Keep the spare offsite; [workstation setup](setup.md#age-identity) registers existing keys. Losing both keys prevents decryption of hardware-only files. A surviving Flux key can decrypt cluster Secrets only.

## Run commands with credentials

| Operation | Files decrypted from `secrets/` |
|---|---|
| OpenTofu init/output/state/show/workspace | `state.sops.yaml` |
| OpenTofu plan/apply/destroy | State, provider and server WireGuard files |
| `wireguard:configure` | State, server and workstation WireGuard files |
| `wireguard:recover` | State and server WireGuard; configure step also loads workstation key |

Touch the YubiKey for each file. The helpers inherit the process environment; clear stale exported tokens first.

```bash
bash scripts/sops-exec.sh secrets/state.sops.yaml -- tofu -chdir=tofu output -raw public_ipv4
```

`sops-exec.sh` accepts flat YAML with single-line environment values. For multiline content, use [SOPS exec-file](https://getsops.io/docs/usage/advanced/#passing-secrets-to-other-processes).

## Create a cluster secret

Use one Kubernetes Secret per encrypted file. Keep metadata readable and encrypt `data`/`stringData`; an encrypted `kind: List` loses its SOPS metadata when Kustomize unwraps it.

```bash
sops edit 'clusters/shire/apps/<APP>/<SECRET>.sops.yaml'
```

Register the file in the owning `kustomization.yaml`. For generated values:

```bash
bash scripts/refresh-sops-secret.sh '<TARGET.sops.yaml>' '<NAMESPACE>' '<NAME>' '<KEY>' -- '<PRODUCER>'
bash scripts/encrypt-sops.sh '<TARGET.sops.yaml>' json -- '<MANIFEST_PRODUCER>'
```

Both helpers replace the target only after production and encryption succeed. [SOPS stdin encryption](https://getsops.io/docs/usage/advanced/#encrypting-and-decrypting-from-other-programs).

## Token inventory

| Credential | Consumer / source |
|---|---|
| Provider credentials | [providers.tf](../tofu/providers.tf), `secrets/tofu.sops.yaml` |
| State S3 credentials | [backend.tf](../tofu/backend.tf), `secrets/state.sops.yaml` |
| Backup S3 credentials | Separate cluster Secrets for etcd, Wanderbound and Quizmon. Quizmon input refresh preserves its backup Secret. |
| Flux GitHub App | `clusters/shire/flux-system/flux-github-app.sops.yaml`; Actions environment `flux-image-automation`: `FLUX_APP_ID` / `FLUX_APP_PRIVATE_KEY` |
| Controller and application credentials | Secret references in their manifests; encrypted files beside those manifests |

| Generated credential | Refresh command |
|---|---|
| Cloudflare Tunnel | `mise run tunnel:refresh` |
| Hetzner CSI | `mise run hcloud-csi:refresh-token` |
| Tailscale operator | `mise run tailscale-operator:refresh-oauth` |

### Backup storage

Create runtime S3 keys in the empty Hetzner `backup-credentials` project. Keys inherit access to every bucket in their own project, so keep buckets out of it. [Hetzner permissions](https://docs.hetzner.com/storage/object-storage/faq/s3-credentials/#how-do-i-restrict-access-per-key).

[backups.tf](../tofu/backups.tf) grants each key access to its paths in `shire-backups`: etcd can write `etcd/`; Wanderbound uses `cnpg/wanderbound/` and `app-data/wanderbound/`; Quizmon uses `cnpg/quizmon/`. Database keys can list all backup filenames for Barman's bucket check. None can access state storage or permanently delete object versions.

To rotate, encrypt the replacement in its cluster Secret and update `TF_VAR_backup_s3_principals` in `secrets/tofu.sops.yaml`. Apply the bucket policy before deploying the Secret. Run a backup and check recovery access before revoking the old key. Never revoke the provisioning/state key when removing its old runtime copies.

## Rotation

| Key | Procedure |
|---|---|
| API token | Issue a replacement; update its encrypted source and derived Secrets; verify consumers; revoke the old token. |
| Hardware key | Generate replacement keys using [bootstrap policies](../bootstrap/bootstrap.sh). Replace the retired recipient in `.sops.yaml`, run `sops updatekeys` on tracked encrypted files, and verify with only the new key connected. Register and test its SSH signing key before retiring the old one. Update `TF_VAR_ssh_public_key_path` if the rescue key changes. |
| Flux age key | Add the new recipient, rewrap cluster files, and store both private identities in the live `sops-age` Secret and encrypted bootstrap file. Reconcile, then remove the old recipient and identity after testing the new one. [Multi-key format](https://fluxcd.io/flux/guides/mozilla-sops/). |
| State passphrase | Follow [OpenTofu encryption migration](https://opentofu.org/docs/language/state/encryption/); retain the old read method during migration and keys for historical state. |
| Etcd backup key | Update the recipient in [talos-backup.yaml](../clusters/shire/infrastructure/controllers/talos-backup.yaml) and encrypted private key in `bootstrap/`. Verify a new snapshot; retain keys needed by older backups. |

Commit recipient changes with the rewrapped files. Re-encryption leaves old Git ciphertext readable by old keys; compromised credentials also require rotation. The commit check validates ciphertext fields, recipients and metadata without decrypting. Only SOPS decryption verifies the MAC.
