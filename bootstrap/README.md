# Bootstrap

Run [bootstrap.sh](bootstrap.sh) once to create keys and credentials. Keep them
for rebuilds. For another workstation, use [setup](../docs/setup.md#set-up-a-workstation).

## Prerequisites

- Install the tools in [workstation setup](../docs/setup.md#tools) and authenticate
  `gh` with permission to manage the repository, Actions secrets and SSH signing keys.
- Have two YubiKeys with unused age slot 1 and space for resident SSH keys.
- Prepare the provider credentials in the [token inventory](../docs/secrets.md#token-inventory),
  the three Cloudflare login addresses, and the Wanderbound upload credential's
  project and access-key IDs.
- Install the Flux GitHub App on the repository. Have its App ID, installation
  ID and private-key PEM file ready. Flux needs repository contents access;
  the image-update workflow also needs pull-request write access.
  [Flux GitHub App setup](https://fluxcd.io/flux/components/source/gitrepositories/#github).

Bootstrap refuses to overwrite `.sops.yaml`, `secrets/`, either encrypted backup
key, the Flux App secret, or its SSH key files. Use [key rotation](../docs/secrets.md)
to replace credentials in an initialized repository.

See [trust roots](../docs/secrets.md#trust-roots) for key roles and touch policies.

## Run

From the repository root:

```bash
mise install
bash bootstrap/bootstrap.sh
```

Enter credentials at the hidden prompts. Connect one YubiKey at a time when
prompted. The script saves age identity references in `SOPS_AGE_KEY_FILE`, or
`~/.config/sops/age/keys.txt` by default, preserving existing entries. It creates
SSH handles under `~/.ssh`; set `BOOTSTRAP_SSH_KEY_DIR` to use another directory.

The script registers both SSH signing keys with GitHub, configures global Git
signing, uploads `FLUX_APP_ID` and `FLUX_APP_PRIVATE_KEY` as Actions secrets,
and replaces repository branch protection and rulesets with `.github/rulesets/`.

## Generated files

| File | Consumer |
|---|---|
| `.sops.yaml` | SOPS encryption rules |
| `bootstrap/cluster-age-key.sops.txt` | Flux `flux-system/sops-age` Secret, installed during rebuild |
| `bootstrap/etcd-backup-age-key.sops.txt` | Etcd snapshot recovery |
| `secrets/state.sops.yaml` | OpenTofu backend and state encryption |
| `secrets/tofu.sops.yaml` | Provider credentials and Cloudflare account addresses |
| `secrets/wireguard.sops.yaml` | Talos WireGuard configuration |
| `secrets/workstation.sops.yaml` | Workstation WireGuard private key |
| `clusters/shire/flux-system/flux-github-app.sops.yaml` | Flux repository authentication |

Bootstrap also sets `AGE_X25519_PUBLIC_KEY` in
[`talos-backup.yaml`](../clusters/shire/infrastructure/controllers/talos-backup.yaml)
to the generated etcd key's public recipient. Both bootstrap private keys are
encrypted to the YubiKeys. Cluster Secrets also include the Flux recipient.

## Verify

```bash
mise run check
sops decrypt bootstrap/cluster-age-key.sops.txt | age-keygen -y
sops decrypt bootstrap/etcd-backup-age-key.sops.txt | age-keygen -y
gh secret list
```

Match the printed recipients to `.sops.yaml` and `talos-backup.yaml`, respectively.
Confirm both `FLUX_APP_*` names in GitHub. Review and commit the files before
[rebuilding](../docs/setup.md#rebuild-the-cluster); store the backup YubiKey offsite.
