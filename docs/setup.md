# Setup

Use the existing YubiKeys and encrypted files. For initial key creation,
see [bootstrap](../bootstrap/README.md).

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

For PIV connection failures, see [YubiKey troubleshooting](troubleshooting.md#the-workstation-cannot-access-the-yubikey).

### Age identity

With the existing YubiKey plugged in, recover its slot-1 identity reference:

```bash
umask 077
mkdir -p ~/.config/sops/age
age-plugin-yubikey --identity --slot 1 >> ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

Skip existing references. Private keys stay on the YubiKey. [Plugin documentation](https://github.com/str4d/age-plugin-yubikey#configuration).

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

Rebuilds require `origin` to match [gotk-sync.yaml](../clusters/shire/flux-system/gotk-sync.yaml),
using SSH or HTTPS. `gh auth setup-git` configures HTTPS credentials.
[mise.toml](../mise.toml) also sets the SSH public-key path.

## Connect to the existing cluster

`wireguard:configure` activates `/etc/wireguard/shire.conf`.
`configs:refresh` overwrites `~/.kube/config` and `~/.talos/config` with mode
`600` after validating both outputs. Save existing contexts first.

```bash
mise run tofu:init
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

`mise run doctor` tests signing, decryption, sudo and state access. `rebuild`
runs that preflight, applies OpenTofu with `-auto-approve`, and commits and
pushes the regenerated Tunnel token. It can replace the server:

```bash
mise run rebuild
```

[rebuild.sh](../scripts/rebuild.sh) provisions the image and server, configures
WireGuard and local clients, and installs Flux with its GitHub App credentials
and SOPS key.

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
