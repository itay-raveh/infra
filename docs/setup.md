# Setup

Use the existing keys and encrypted files. [Bootstrap](../bootstrap/README.md) is for initial credential creation.

## Set up a workstation

### Tools

Install [mise](https://mise.jdx.dev/getting-started.html). On Debian or Ubuntu:

```bash
sudo apt-get install -y pcscd libpcsclite-dev build-essential swig python3-dev wireguard-tools
sudo systemctl enable --now pcscd.socket
mise install
prek install
```

### Age identity

Match the connected key's recipient to [.sops.yaml](../.sops.yaml), then register its identity reference. Skip references already present.

```bash
age-plugin-yubikey --list
umask 077
mkdir -p ~/.config/sops/age
age-plugin-yubikey --identity --serial '<SERIAL>' --slot '<SLOT>' >> ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

### Git signing

Recover the resident SSH key into `~/.ssh`; `<DOWNLOADED_KEY>` is the handle created by `ssh-keygen -K`.

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
git config --global user.name '<YOUR_NAME>'
git config --global user.email '<YOUR_EMAIL>'
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519_sk.pub
git config --global commit.gpgsign true
gh auth login
gh auth setup-git
```

## Connect to the existing cluster

`configs:refresh` replaces `~/.kube/config` and `~/.talos/config`; save other contexts first. `wireguard:configure` installs and activates `/etc/wireguard/shire.conf`.

```bash
mise run tofu:init
mise run wireguard:configure
mise run configs:refresh
sudo wg show shire
kubectl get nodes
talosctl health
```

Expected: a recent WireGuard handshake and a `Ready` node. See [troubleshooting](troubleshooting.md#management-apis-are-unreachable) if either fails.

## Rebuild the cluster

Requires a clean `main` tracking `origin/main`, the YubiKey, sudo and permission to push the generated Tunnel token. `origin` must match [gotk-sync.yaml](../clusters/shire/flux-system/gotk-sync.yaml).

**This can replace the server and bootstrap an empty cluster.** For an etcd restore, use [recovery](disaster-recovery.md#restore-etcd).

```bash
mise run rebuild
flux get kustomizations --watch
kubectl get nodes
```

[rebuild.sh](../scripts/rebuild.sh) runs preflight checks, applies OpenTofu with `-auto-approve`, configures management access, opens a PR for the Tunnel token, waits for CI and squash merge, then installs Flux and its credentials. If that PR fails or remains unmerged for 30 minutes, the script stops before installing Flux. Application data requires a [separate restore](disaster-recovery.md).

## Account prerequisites

| Dependency | Configuration |
|---|---|
| Hetzner project and existing state bucket | [providers.tf](../tofu/providers.tf), [backend.tf](../tofu/backend.tf) |
| Cloudflare account, zone and tokens | [Cloudflare](cloudflare.md) |
| Tailscale tailnet and OAuth client | [tailscale.tf](../tofu/tailscale.tf) |
| Flux GitHub App | `clusters/shire/flux-system/flux-github-app.sops.yaml`; Actions environment `flux-image-automation`: `FLUX_APP_ID` and `FLUX_APP_PRIVATE_KEY` |
| Hardware, Flux and etcd keys | [Bootstrap](../bootstrap/README.md), [Secrets](secrets.md) |
