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

Flux keeps its private key in `flux-system/sops-age`. That key unlocks cluster
secrets, including application credentials. Hardware-only files require a
YubiKey.

OpenTofu encrypts state and saved plans using the passphrase in
`secrets/state.sops.yaml`. State contains Talos PKI and provider resource secrets.
Local kubeconfig, talosconfig and WireGuard files contain plaintext credentials.

## Run a command

Use the existing `mise` tasks. The [OpenTofu wrapper](../scripts/tofu-wrapper.sh)
selects the files for each operation:

| Operation | Files loaded from `secrets/` |
|---|---|
| OpenTofu init, output, state, show and workspace | `state.sops.yaml` |
| OpenTofu plan, apply and destroy | `state.sops.yaml`, `tofu.sops.yaml`, `wireguard.sops.yaml` |
| `wireguard:configure` | `state.sops.yaml`, `wireguard.sops.yaml`, `workstation.sops.yaml` |
| `wireguard:recover` | `state.sops.yaml`, `wireguard.sops.yaml`; its configure step also loads the workstation key |

Expect a YubiKey touch for each file. These commands do not cache decrypted
values or export them into your interactive shell. They retain the rest of the
inherited environment, so start from a shell without previously exported tokens.

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

The helper captures producer and encryption failures before replacing the target.
It writes only ciphertext to a temporary file in the destination directory.
Pass the producer after `--`; an outer pipeline cannot report its failure to the
helper before the helper replaces the target.

For a full manifest, use `bash scripts/encrypt-sops.sh <TARGET> json -- <PRODUCER>`.
Replace `json` with `yaml` or `binary` to match the producer's output. The helper
selects the SOPS creation rule using the final filename.
[SOPS stdin encryption](https://getsops.io/docs/usage/advanced/#encrypting-and-decrypting-from-other-programs).
The [sanity hook](../scripts/sops-sanity.sh) checks for ciphertext markers;
test decryption separately when changing recipients.

## Token inventory

The following entries describe the repository's consumers. Verify granted
permissions, token IDs and expiration dates at the issuer before rotation.

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
| Database backup S3 credentials | `clusters/shire/apps/wanderbound/cnpg-s3-creds.sops.yaml` | CloudNativePG backups |
| Upload S3 credentials | `clusters/shire/apps/wanderbound/wanderbound-upload-s3-creds.sops.yaml` | Backend uploads; the project/access-key IDs in `tofu.sops.yaml` identify its bucket-policy principal |
| Sentry sourcemap token | `clusters/shire/apps/wanderbound/wanderbound-sourcemaps-secrets.sops.yaml` | Sourcemap upload job |

Two credentials still span unrelated consumers: the provisioning token also
serves CSI, and the analytics token also serves account administration. Creating
dedicated tokens requires a permissions review at Hetzner and Cloudflare.
The file split preserves their existing permissions and values.

Application signing keys, the Google OAuth client secret and Sentry DSN live in
`clusters/shire/apps/wanderbound/wanderbound-secrets.sops.yaml`. The Restic
password lives in `wanderbound-backup-secrets.sops.yaml` beside it. Keep backup
passwords and decryption keys while their backups remain in use.

## Replace an API token

1. Identify its issuer and consumers in the inventory. Record the issuer's token
   ID, resource scope, granted permissions and expiry beside the entry.
2. Create a replacement at the issuer. Keep the old token active during deployment
   unless you are responding to a compromise.
3. Update its SOPS value with `sops edit`. For generated Kubernetes Secrets,
   update the source and run the corresponding refresh task.
4. Verify the consumer. Run `mise run tofu:plan` for provider credentials. For a
   cluster credential, commit and deploy the encrypted manifest, then check the
   affected controller or application.
5. Revoke the old token at the issuer after verification. Record the replacement
   date and new token ID. Before revocation, rollback means restoring the old
   encrypted value and redeploying it.

Re-encrypting a file does not revoke its tokens. Git history retains old
ciphertext. [Secret lifecycle guidance](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html#27-secret-lifecycle).

## Replace a hardware key

1. Generate age and SSH keys on the replacement YubiKey. Use the
   [age plugin](https://github.com/str4d/age-plugin-yubikey#configuration) and
   SSH options from [bootstrap.sh](../bootstrap/bootstrap.sh), with new local
   filenames.
2. Replace the retired recipient in `.sops.yaml`. Keep the surviving hardware
   recipient and the Flux recipient.
3. List encrypted files with `git ls-files '*.sops.*'`, then run
   `sops updatekeys <FILE>` on each, including both bootstrap keys.
4. Test decryption using only the new hardware identity. Register the new SSH
   public key with GitHub, update `user.signingkey`, and test signing.
5. Commit the rewrapped files. If the Hetzner rescue SSH key changed, plan and
   apply that change through OpenTofu.

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
