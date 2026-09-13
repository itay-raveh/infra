# Setup

These instructions use the existing YubiKeys and encrypted files in the repo.
For a new environment, start with the [bootstrap script's outstanding work](../bootstrap/README.md#bootstrapsh).

## Set up a workstation

### Tools

On Debian or Ubuntu:

```bash
sudo apt-get install -y pcscd libpcsclite-dev build-essential swig python3-dev wireguard-tools
sudo systemctl enable --now pcscd.socket
```

Install and activate [mise](https://mise.jdx.dev/getting-started.html), then:

```bash
mise install
prek install
```

### Age identity

With the existing YubiKey plugged in, recover its slot-1 identity reference:

```bash
mkdir -p ~/.config/sops/age
umask 077
age-plugin-yubikey --identity --slot 1 >> ~/.config/sops/age/keys.txt
```

Skip this if the reference is already in `keys.txt`. The private key stays on
the YubiKey. [Plugin documentation](https://github.com/str4d/age-plugin-yubikey#configuration).

### Git signing

Download the resident SSH key into `~/.ssh`. Replace `<DOWNLOADED_KEY>` with
the handle written by `ssh-keygen -K`:

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

```bash
git config --global user.name '<YOUR_NAME>'
git config --global user.email '<YOUR_EMAIL>'
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519_sk.pub
git config --global commit.gpgsign true
gh auth login
gh auth setup-git
```

`origin` must use the HTTPS URL in
[gotk-sync.yaml](../clusters/shire/flux-system/gotk-sync.yaml) for rebuilds.
The SSH public-key path is also set in [mise.toml](../mise.toml).

## Connect to the existing cluster

`wireguard:configure` installs and activates `/etc/wireguard/shire.conf`.
`configs:refresh` overwrites `~/.kube/config` and `~/.talos/config`; save any
existing contexts first.

```bash
mise run wireguard:configure
mise run configs:refresh
sudo wg show shire
kubectl get nodes
talosctl health
```

The WireGuard peer should have a recent handshake and the node should be
`Ready`. See [connection failures](troubleshooting.md#management-apis-are-unreachable).

## Rebuild the cluster

Requires a clean `main` checkout tracking `origin/main`, the YubiKey, sudo,
and GitHub admin access with the existing ruleset's push bypass.

For an etcd snapshot restore, start with [recovery](disaster-recovery.md#restore-etcd)
before running `rebuild`.

```bash
mise run doctor
```

The preflight tests signing and decryption, requests sudo, and opens the state
backend.

`rebuild` applies OpenTofu with `-auto-approve`, can replace the server, and
commits and pushes the regenerated Tunnel token:

```bash
mise run rebuild
```

It provisions the image and server, configures WireGuard, writes the local
client configs, and installs Flux with its GitHub App credentials and SOPS key.
The steps are in [rebuild.sh](../scripts/rebuild.sh).

```bash
flux get kustomizations --watch
kubectl get nodes
curl -sSI https://raveh.dev
curl -sSI https://unconfigured.raveh.dev
```

Expect ready Flux resources, an apex redirect to `https://itay.raveh.dev/`,
and a 404 for the unconfigured hostname.

Application data needs [a separate restore](disaster-recovery.md).

## Account prerequisites

| Dependency | Reference |
|---|---|
| Hetzner project and provider credentials | [providers.tf](../tofu/providers.tf), `secrets/tofu.sops.yaml`, `secrets/state.sops.yaml` |
| Existing `shire-tfstate` Object Storage bucket | [backend.tf](../tofu/backend.tf) |
| Cloudflare account, zone and API tokens | [Cloudflare](cloudflare.md) |
| Tailscale tailnet and OAuth client | [tailscale.tf](../tofu/tailscale.tf) |
| Flux GitHub App | `flux-github-app.sops.yaml` in `clusters/shire/flux-system/`; GitHub Actions secrets `FLUX_APP_ID` and `FLUX_APP_PRIVATE_KEY` |
| Flux and etcd backup keys | [bootstrap/](../bootstrap/README.md) |
