# Set up access and rebuild the cluster

Use the workstation procedure to access the existing environment. A cluster
rebuild is a separate operation that can replace infrastructure and does not
restore application data.

## Set up a workstation

You need an existing repository clone, a configured YubiKey, access to the
Hetzner state bucket, and a GitHub session with repository access. Initial
account provisioning is described under [external prerequisites](#external-prerequisites).

### Install tools

On Debian or Ubuntu, install the WireGuard tools and dependencies needed by
the YubiKey tools:

```bash
sudo apt-get install -y pcscd libpcsclite-dev build-essential swig python3-dev wireguard-tools
sudo systemctl enable --now pcscd.socket
```

With [mise installed](https://mise.jdx.dev/getting-started.html), run from
the repository root:

```bash
mise install
prek install
```

Activate mise in your shell so the pinned tools are on `PATH`. Compare
`tofu version` with `required_version` in
[tofu/versions.tf](../tofu/versions.tf) before running OpenTofu tasks.
If the pins disagree, follow [version troubleshooting](troubleshooting.md#opentofu-version-mismatch).

### Restore the age identity reference

On a new workstation, reconstruct the reference to the existing YubiKey key.
The bootstrap script uses slot 1. Plug in that YubiKey and run:

```bash
mkdir -p ~/.config/sops/age
umask 077
age-plugin-yubikey --identity --slot 1 >> ~/.config/sops/age/keys.txt
```

This writes an identity reference, not the private key stored on the hardware.
Skip this step if the matching reference is already present. See the
[plugin's identity recovery instructions](https://github.com/str4d/age-plugin-yubikey#configuration).

### Restore Git signing

Download the resident SSH key handle into `~/.ssh`. `ssh-keygen -K` writes to
the current directory. Replace `<DOWNLOADED_KEY>` below with the downloaded
private-key handle's filename, and avoid overwriting an existing key:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cd ~/.ssh
ssh-keygen -K
mv -i '<DOWNLOADED_KEY>' id_ed25519_sk
mv -i '<DOWNLOADED_KEY>.pub' id_ed25519_sk.pub
chmod 600 id_ed25519_sk
chmod 644 id_ed25519_sk.pub
cd -
```

Configure signing and HTTPS authentication:

```bash
git config --global user.name '<YOUR_NAME>'
git config --global user.email '<YOUR_EMAIL>'
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519_sk.pub
git config --global commit.gpgsign true
gh auth login
gh auth setup-git
```

For rebuilds, the `origin` push URL must match the HTTPS URL in
[gotk-sync.yaml](../clusters/shire/flux-system/gotk-sync.yaml). The SSH public-key
path must also match `TF_VAR_ssh_public_key_path` in [mise.toml](../mise.toml).
If a signing operation fails, repair access to the signing key before retrying.

### Connect to the existing cluster

The following tasks decrypt credentials from `tofu/secrets.sops.yaml`.
`wireguard:configure` installs `/etc/wireguard/shire.conf` and activates it.
`configs:refresh` overwrites `~/.kube/config` and `~/.talos/config`; preserve any
other contexts stored in those files first.

```bash
mise run wireguard:configure
mise run configs:refresh
sudo wg show shire
kubectl get nodes
talosctl health
```

Expect a recent WireGuard handshake, a Kubernetes node with status `Ready`,
and successful Talos health checks. If access fails, use
[management connection troubleshooting](troubleshooting.md#management-apis-are-unreachable).

## Rebuild the cluster

Before replacing a server, inspect the plan and confirm which data must be
[restored from backup](disaster-recovery.md). An etcd snapshot recovery needs
an unbootstrapped control plane; do not run this rebuild procedure first.

The rebuild requires a clean checkout of the branch watched by Flux, tracking
its `origin` branch. It also requires GitHub admin push access permitted by
the repository's existing ruleset.

Run the preflight separately to find missing prerequisites:

```bash
mise run doctor
```

[doctor.sh](../scripts/doctor.sh) checks tools, Git configuration, repository
permissions, encrypted files, hardware access and the state backend. It tests
SSH signing, decrypts secrets, requests sudo authentication and initializes
the backend. It does not apply infrastructure.

**The next command applies OpenTofu plans with automatic approval and can
replace the server. It also rebases the checkout and commits and pushes the
regenerated Cloudflare Tunnel token.**

```bash
mise run rebuild
```

[rebuild.sh](../scripts/rebuild.sh) runs the preflight, provisions the image
and stable IP, configures workstation WireGuard, applies the remaining
infrastructure, writes local client configurations, publishes the Tunnel
token, and seeds Flux with its decryption key and GitHub App credentials.

Check reconciliation and public routing after it completes:

```bash
flux get kustomizations --watch
kubectl get nodes
curl -sSI https://raveh.dev
curl -sSI https://unconfigured.raveh.dev
```

Flux resources should become ready. The apex should redirect to
`https://itay.raveh.dev/`; an unconfigured wildcard hostname should return 404.
Restore and verify application data separately.

## External prerequisites

The existing environment depends on these resources and credentials:

| Dependency | Configuration |
|---|---|
| Hetzner Cloud project and API access | [tofu/providers.tf](../tofu/providers.tf), encrypted provider variables |
| Object Storage state bucket `shire-tfstate` | [tofu/backend.tf](../tofu/backend.tf); the bucket must exist before backend initialization |
| Cloudflare account, zone and API tokens | Provider aliases in [tofu/providers.tf](../tofu/providers.tf) |
| Tailscale tailnet and provider OAuth client | [tofu/tailscale.tf](../tofu/tailscale.tf) |
| Flux GitHub App and repository access | `clusters/shire/flux-system/flux-github-app.sops.yaml`; workflow secrets `FLUX_APP_ID` and `FLUX_APP_PRIVATE_KEY` |
| Software recovery keys | [bootstrap artifacts](../bootstrap/README.md) |

[bootstrap/bootstrap.sh](../bootstrap/bootstrap.sh) does not currently create
all of these prerequisites. Read its [limitations](../bootstrap/README.md#initial-provisioning-script)
before using it for a new environment.
