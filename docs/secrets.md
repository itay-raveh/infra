# Secrets

[.sops.yaml](../.sops.yaml) assigns recipients by path:

| File | Contents | Decryption key |
|---|---|---|
| `secrets/state.sops.yaml` | State encryption passphrase and S3 backend credentials | Either YubiKey |
| `secrets/tofu.sops.yaml` | Provider credentials, upload-policy identifiers and Cloudflare login addresses | Either YubiKey |
| `secrets/wireguard.sops.yaml` | Server private key and workstation public key | Either YubiKey |
| `secrets/workstation.sops.yaml` | Workstation private key | Either YubiKey |
| `bootstrap/*.sops.txt` | Flux and etcd backup decryption keys | Either YubiKey |
| `clusters/**/*.sops.yaml` and `*.sops.json` | Kubernetes Secrets | Either YubiKey or the Flux age key |

Flux stores its private key in `flux-system/sops-age`. OpenTofu encrypts state
and saved plans with the state passphrase. State holds Talos PKI and resource
secrets; local kubeconfig, talosconfig and WireGuard files hold plaintext credentials.

## Trust roots

Each YubiKey has independent PIV age keys in slot 1 and a resident FIDO2 SSH
signing key. [Bootstrap](../bootstrap/bootstrap.sh) requires a touch for both,
with no PIN for age. [Workstation setup](setup.md#set-up-a-workstation)
recovers their local identity references.

GitHub registers both signing keys. Hetzner uses the rescue key selected by
`TF_VAR_ssh_public_key_path` in [mise.toml](../mise.toml); changing it requires
an OpenTofu apply. Keep the backup YubiKey offsite.

## Protection and limits

| Failure | Protection and recovery |
|---|---|
| Repository disclosure | SOPS encrypts secret values. OpenTofu state and plans use AES-GCM, configured in [backend.tf](../tofu/backend.tf). |
| Accidental plaintext commit | Betterleaks and the SOPS sanity hook run locally and in CI. They do not prove that every credential is encrypted. |
| Workstation compromise | Hardware keys remain on the YubiKey, but local client configs and credentials in running processes are accessible to a compromised workstation. |
| Cluster compromise | Access to `flux-system/sops-age` exposes the cluster files in the table above. That key cannot decrypt `secrets/` or `bootstrap/`. |
| Loss of one YubiKey | The surviving key can decrypt all SOPS files. [Replace the lost key](#replace-a-hardware-key). |
| Loss of both YubiKeys | Hardware-only files cannot be decrypted. A surviving Flux key can recover cluster Secrets, but cannot recover the state passphrase or bootstrap keys. |

## Run a command

Use the existing `mise` tasks. The [OpenTofu wrapper](../scripts/tofu-wrapper.sh)
selects the files for each operation:

| Operation | Files loaded from `secrets/` |
|---|---|
| OpenTofu init, output, state, show and workspace | `state.sops.yaml` |
| OpenTofu plan, apply and destroy | `state.sops.yaml`, `tofu.sops.yaml`, `wireguard.sops.yaml` |
| `wireguard:configure` | `state.sops.yaml`, `wireguard.sops.yaml`, `workstation.sops.yaml` |
| `wireguard:recover` | `state.sops.yaml`, `wireguard.sops.yaml`; its configure step also loads the workstation key |

Touch the YubiKey for each file. Values are neither cached nor exported to
your shell. Other environment variables are inherited: clear previously
exported tokens before running.

For another command, pass flat YAML credential files and an argument list to
[sops-exec.sh](../scripts/sops-exec.sh):

```bash
bash scripts/sops-exec.sh secrets/state.sops.yaml -- \
  tofu -chdir=tofu output -raw public_ipv4
```

The helper checks for empty values and uses `sops exec-env --same-process`.
Keep environment credentials on one line. For multiline file contents, use
[`sops exec-file`](https://getsops.io/docs/usage/advanced/#passing-secrets-to-other-processes),
which supplies a FIFO by default.

## Edit a secret

```bash
sops edit secrets/tofu.sops.yaml
```

SOPS opens plaintext in `$EDITOR` and encrypts it on save. Cluster manifests
leave metadata readable and encrypt `data` and `stringData`.

## Create a cluster secret

Open the final path with SOPS, replace the template with a Secret manifest,
and add the file to its directory's `kustomization.yaml`:

```bash
sops edit clusters/shire/apps/wanderbound/example.sops.yaml
```

For a generated token, pass its producer command to the refresh helper:

```bash
bash scripts/refresh-sops-secret.sh \
  clusters/shire/infrastructure/controllers/cloudflared-tunnel-token.sops.yaml \
  cloudflared cloudflared-tunnel-token cf-tunnel-token -- \
  bash scripts/tofu-wrapper.sh output -raw tunnel_token
```

The helper replaces the target only after production and encryption succeed.
Its temporary file contains ciphertext. Pass the producer after `--`; an outer
pipeline cannot report producer failure before replacement.

For a full manifest, use `bash scripts/encrypt-sops.sh <TARGET> json -- <PRODUCER>`.
Replace `json` with `yaml` or `binary` to match the producer's output. The helper
selects the SOPS creation rule using the final filename.
[SOPS stdin encryption](https://getsops.io/docs/usage/advanced/#encrypting-and-decrypting-from-other-programs).
The [sanity hook](../scripts/sops-sanity.sh) checks for ciphertext markers;
test decryption separately when changing recipients.

## Token inventory

Verify permissions, token IDs and expiry at the issuer before rotation.

| Credential | Stored value | Consumers |
|---|---|---|
| Hetzner state storage | `state.sops.yaml`: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | S3 backend in [backend.tf](../tofu/backend.tf) |
| Hetzner bucket management | `tofu.sops.yaml`: `TF_VAR_s3_access_key_id`, `TF_VAR_s3_secret_access_key` | MinIO and AWS providers in [providers.tf](../tofu/providers.tf) |
| Hetzner provisioning | `tofu.sops.yaml`: `TF_VAR_hcloud_token` | Hetzner and image providers; `hcloud-csi:refresh-token` copies it to the CSI Secret |
| Cloudflare zone and services | `tofu.sops.yaml`: `TF_VAR_cloudflare_api_token` | Default Cloudflare provider |
| Cloudflare analytics and account administration | `tofu.sops.yaml`: `TF_VAR_cloudflare_web_analytics_api_token` | Both `web_analytics` and `account` provider aliases |
| Tailscale provisioning OAuth client | `tofu.sops.yaml`: `TAILSCALE_OAUTH_CLIENT_ID`, `TAILSCALE_OAUTH_CLIENT_SECRET` | Tailscale provider; requested scopes are in [providers.tf](../tofu/providers.tf) |
| Sentry administration | `tofu.sops.yaml`: `SENTRY_AUTH_TOKEN` | Monitors in [sentry.tf](../tofu/sentry.tf) |
| Cloudflare Tunnel token | OpenTofu state; generated `cloudflared-tunnel-token.sops.yaml` | cloudflared; update with `mise run tunnel:refresh` |
| Tailscale operator OAuth client | OpenTofu state; generated `tailscale-operator-oauth.sops.yaml` | Kubernetes operator; update with `mise run tailscale-operator:refresh-oauth` |
| Flux GitHub App private key | `clusters/shire/flux-system/flux-github-app.sops.yaml`; GitHub Actions `FLUX_APP_PRIVATE_KEY` | Flux Git access and the image-update PR workflow |
| Etcd backup S3 credentials | `clusters/shire/infrastructure/controllers/s3-backup-creds.sops.yaml` | Talos backup job |
| Database and file backup S3 credentials | `clusters/shire/apps/wanderbound/cnpg-s3-creds.sops.yaml` | CloudNativePG and restic backups |
| Upload S3 credentials | `clusters/shire/apps/wanderbound/wanderbound-upload-s3-creds.sops.yaml` | Backend uploads; the project/access-key IDs in `tofu.sops.yaml` identify its bucket-policy principal |
| Sentry sourcemap token | `clusters/shire/apps/wanderbound/wanderbound-sourcemaps-secrets.sops.yaml` | Sourcemap upload job |

`wanderbound-secrets.sops.yaml` holds application signing keys, the Google
OAuth secret and Sentry DSN. `wanderbound-backup-secrets.sops.yaml` holds the
Restic password. Keep backup passwords and keys while their backups are needed.

## Replace an API token

1. Find the issuer and consumers above. Record token ID, scope, permissions and expiry.
2. Issue a replacement. Keep the old token active unless compromised.
3. Update with `sops edit`; regenerate derived Secrets with their refresh tasks.
4. Verify provider credentials with `mise run tofu:plan`. Deploy cluster Secrets
   and check their consuming controller or application.
5. Revoke the old token, then record the new ID and rotation date. Before revocation,
   roll back by restoring and deploying the old encrypted value.

Re-encryption does not revoke tokens or erase old ciphertext from Git. [Secret lifecycle guidance](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html#27-secret-lifecycle).

## Replace a hardware key

1. Connect only the replacement YubiKey, with unused age slot 1 and space for
   a resident SSH key. Generate both keys with the bootstrap policies. Use an
   unused SSH filename:

   ```bash
   age-plugin-yubikey --generate --slot 1 --touch-policy always --pin-policy never \
     >> ~/.config/sops/age/keys.txt
   age-plugin-yubikey --list --slot 1
   ssh-keygen -t ed25519-sk -O resident -O application=ssh:yubikey-replacement \
     -f ~/.ssh/id_ed25519_sk_replacement -C yubikey-replacement
   ```

   Record the new age recipient printed by `--list`.
2. Replace the retired recipient in `.sops.yaml`. Keep the surviving hardware
   recipient and the Flux recipient.
3. Connect the surviving YubiKey to decrypt the old recipients. List files with
   `git ls-files '*.sops.*'`, then run `sops updatekeys '<FILE>'` on each,
   including both bootstrap keys.
4. Reconnect only the replacement key and test decryption of the rewrapped
   files, directing plaintext to `/dev/null`. Register its SSH public key:

   ```bash
   gh ssh-key add ~/.ssh/id_ed25519_sk_replacement.pub --type signing --title yubikey-replacement
   ```

   If replacing the primary, set Git's `user.signingkey` and mise's
   `TF_VAR_ssh_public_key_path` to the new public-key path. Test signing before
   removing the retired signing key from GitHub.
5. Commit `.sops.yaml` and the rewrapped files together. If the Hetzner rescue
   SSH key changed, plan and apply that change through OpenTofu.
6. Return the backup YubiKey to offsite storage.

Old ciphertext in Git remains readable with the old key. If the key was
compromised, rotate the exposed credentials too.
[SOPS key rotation](https://sops.pages.dev/#key-rotation).

## Rotate the Flux key

1. Add the new public recipient beside the old one in the cluster creation rule.
   Rewrap the cluster SOPS files.
2. Put both private identities in `flux-system/sops-age` and in
   `bootstrap/cluster-age-key.sops.txt`. Encrypt the bootstrap file with SOPS
   binary input/output and its final filename.
3. Commit the rewrapped files and wait for Flux reconciliation.
4. Remove the old recipient, rewrap and commit again. Test decryption with only
   the new identity before removing the old private identity from the live
   Secret and bootstrap file.

[Flux's SOPS guide](https://fluxcd.io/flux/guides/mozilla-sops/) documents the
multi-key Secret format.

## State passphrase

Follow [OpenTofu's encryption migration](https://opentofu.org/docs/language/state/encryption/):
write with the new method and retain the old method as a read fallback during
migration. Keep old passphrases for historical state versions. Replacing
`TF_VAR_encryption_passphrase` alone prevents reads of existing state.

## Etcd backup key

Update the public recipient in
[talos-backup.yaml](../clusters/shire/infrastructure/controllers/talos-backup.yaml)
and the private key in `bootstrap/etcd-backup-age-key.sops.txt`. Test decryption
of a new snapshot. Retain old private keys as long as their snapshots are needed.
