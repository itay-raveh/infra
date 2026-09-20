# Bootstrap

Run [bootstrap.sh](bootstrap.sh) once to create the repository’s keys and credentials. For an existing installation, use [workstation setup](../docs/setup.md#set-up-a-workstation).

## Prerequisites

| Requirement | Details |
|---|---|
| Workstation | [Tools](../docs/setup.md#tools); `gh` authenticated with repository, Actions secrets and SSH signing-key permissions |
| Two YubiKeys | Unused age slot 1 and space for resident SSH keys |
| Provider credentials | Hetzner Cloud, S3, Cloudflare, Tailscale and Sentry; three Cloudflare login addresses |
| Flux GitHub App | Installed on this repository; App ID, installation ID and private-key PEM file. [Permissions](https://fluxcd.io/flux/components/source/gitrepositories/#github): contents access for Flux, pull-request write for image updates |

The script refuses existing keys, `.sops.yaml`, `secrets/` or Flux credentials. See [rotation](../docs/secrets.md#rotation) and [key policies](../docs/secrets.md#trust-roots).

## Run

```bash
mise install
bash bootstrap/bootstrap.sh
```

Credentials are entered at hidden prompts. Connect one YubiKey at a time when prompted.

| Output / side effect | Location |
|---|---|
| Age identity references | `SOPS_AGE_KEY_FILE`, default `~/.config/sops/age/keys.txt`; existing entries preserved |
| Resident SSH handles | `BOOTSTRAP_SSH_KEY_DIR`, default `~/.ssh` |
| Recipients and encryption rules | `.sops.yaml` |
| Flux and etcd private keys | `bootstrap/*.sops.txt`, encrypted to the YubiKeys |
| Provider, state and WireGuard credentials | `secrets/*.sops.yaml` |
| Flux GitHub App credentials | `clusters/shire/flux-system/flux-github-app.sops.yaml`; Actions environment `flux-image-automation`: `FLUX_APP_ID` and `FLUX_APP_PRIVATE_KEY` |
| Etcd backup recipient | `AGE_X25519_PUBLIC_KEY` in [talos-backup.yaml](../clusters/shire/infrastructure/controllers/talos-backup.yaml) |
| Git configuration | Both signing keys registered with GitHub; global SSH commit signing enabled |
| Repository protection | [.github/rulesets/](../.github/rulesets/) applied by name; unrelated rules preserved |

Application-specific credentials belong in `secrets/tofu.sops.yaml` under the `TF_VAR_*` names declared in their `tofu/` files. Add these before planning those resources.

## Verify

```bash
mise run check
sops decrypt bootstrap/cluster-age-key.sops.txt | age-keygen -y
sops decrypt bootstrap/etcd-backup-age-key.sops.txt | age-keygen -y
gh secret list --env flux-image-automation
```

Match the public recipients to `.sops.yaml` and `talos-backup.yaml`; confirm both `FLUX_APP_*` names. Commit the generated files before [rebuilding](../docs/setup.md#rebuild-the-cluster). Store the spare YubiKey offsite.
