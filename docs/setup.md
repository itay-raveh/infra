# Setup

Two paths in one document:

- **One-time setup** runs once in the life of the repo and produces
  committed artifacts that make subsequent rebuilds self-contained.
- **Every-rebuild path** runs on any clean laptop + Hetzner account to
  reach a working cluster in ~20 minutes. This is also the disaster
  recovery path.

If you've never set up this repo before, do One-time setup first. After
that, every cluster rebuild is just the rebuild path.

---

## One-time setup

Do these once, in order. Each step produces artifacts that get committed
to git.

### 1. External prerequisites

These live outside any tool we run; create them manually first.

- **Hetzner Cloud project** with an API token scoped `Read & Write`.
- **Hetzner Object Storage bucket** named `raveh-infra-tfstate` (in `fsn1`),
  plus an S3 credential pair for it. This holds the encrypted tofu state.
- **Cloudflare account** with `raveh.dev` on it. Create an API token
  scoped to `Zone:DNS edit` + `Zero Trust edit` on that one zone.
- **GitHub account** (`itay-raveh`) and a local `gh auth login` session.
- **Tailscale account** with a tailnet, an ACL tag `tag:shire` defined,
  and a reusable pre-auth key for that tag. 90-day expiry is fine because
  the key is captured in SOPS, not re-typed.

### 2. Laptop prerequisites

```
mise install        # reads .mise.toml and pulls every tool
pre-commit install  # activates the local hooks
```

On Linux, also install the PC/SC daemon so `age-plugin-yubikey` can
reach the YubiKey's PIV applet (FIDO2 uses HID directly and works
without it), plus the dev headers and toolchain that `pyscard`
(ykman's smartcard dep) needs to build from source under pipx:

```
sudo apt-get install -y pcscd libpcsclite-dev build-essential swig python3-dev
sudo systemctl enable --now pcscd.socket
```

`ykman` itself is pinned in `.mise.toml` (`pipx:yubikey-manager`), so
`mise install` pulls it in once the build deps above are present. It's used by the pre-ceremony sanity
checks (`ykman piv info`, `ykman fido credentials list`) and for
rotation and troubleshooting, but the bootstrap script itself doesn't
shell out to it.

**Ubuntu 24.04 gotcha:** if you've installed the Yubico Authenticator
from the Snap Store, it ships its own `pcscd` inside the snap and
grabs the USB interface exclusively. The system `pcscd.socket`
silently fails to talk to the YubiKey while the snap is running. Use
the `.deb` from yubico.com instead, or stop the snap before running
any PIV command.

### 3. Run the bootstrap ceremony

Each YubiKey holds two on-device keys in independent applets:

- **PIV slot 1**  - age P-256 key for SOPS (decrypts `.sops.*` files)
- **FIDO2 resident**  - ed25519 SSH key for Hetzner rescue-mode
  break-glass and git commit signing

Both are hardware-generated and unextractable. Run the ceremony with
both YubiKeys nearby:

```
bootstrap/bootstrap.sh
```

The script prompts you to plug in each YubiKey in turn, generates the
age + SSH keys on both, generates the cluster software age key in
memory, registers both SSH pubkeys with GitHub as signing keys, sets
git's global SSH signing config, writes `.sops.yaml` with all three
recipients, encrypts the cluster key to
`bootstrap/cluster-age-key.sops.txt`, generates the tofu state
passphrase (the AES-GCM key for the S3-backed state file) and encrypts
it to `tofu/encryption-passphrase.sops.txt`, prompts you to paste a
fresh Tailscale pre-auth key (generated in the Tailscale admin UI -
instructions print in-terminal) and wraps it to
`talos/tailscale-authkey.sops.txt`, and finally applies repository
rulesets to `main`. From that point on `git commit` requires a touch
on the primary YubiKey.

**Store the backup YubiKey offsite** as soon as the script finishes.

### 4. Commit everything

At this point `.sops.yaml`, `bootstrap/cluster-age-key.sops.txt`,
`tofu/encryption-passphrase.sops.txt`, and
`talos/tailscale-authkey.sops.txt` are all new in the working tree.
Commit and push them. The repo is now self-bootstrapping.

---

## Every-rebuild path

This is the disaster-recovery path and the "I'm setting this up on a
new laptop" path. It assumes the one-time setup artifacts above are
already in git. Target wall-clock: ~20 minutes.

### 1. Local prep

```
git clone git@github.com:itay-raveh/infra.git
cd infra
mise install
pre-commit install
```

Plug in a YubiKey.

### 2. Fill `.env`

Copy `.env.example` to `.env` and fill in:

- `TF_VAR_hcloud_token`  - from Hetzner Cloud console
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`  - the tfstate bucket credential
- `TF_VAR_cloudflare_api_token`, `TF_VAR_cloudflare_zone_id`,
  `TF_VAR_cloudflare_account_id`
- `TF_VAR_ssh_public_key_path`  - absolute path to the primary YubiKey's
  FIDO2-sk pubkey (e.g. `~/.ssh/id_ed25519_sk.pub`). Used only by
  Hetzner rescue-mode break-glass.
- `SOPS_AGE_KEY_FILE`  - path to your age-plugin-yubikey identity stub

Then `gh auth login` so `flux bootstrap github` (step 5) can read
`GITHUB_TOKEN` via `gh auth token`.

### 3. `mise run tofu-apply`

The task unwraps the state passphrase from
`tofu/encryption-passphrase.sops.txt` (one YubiKey touch), exports it,
then runs `tofu apply`. The `sops` Terraform provider reads the
Tailscale auth key from `talos/tailscale-authkey.sops.txt` during the
plan phase (second YubiKey touch). That:

- Builds the custom Talos schematic at the Image Factory (extensions
  baked in: `siderolabs/hcloud`, `qemu-guest-agent`, `tailscale`)
- Uploads the resulting `hcloud-arm64.raw.xz` into Hetzner as a snapshot
  via the `imager` provider
- Creates a CAX21 ARM server from that snapshot in `hel1`
- Creates the persistent `shire-data` Hetzner Volume and attaches it
- Closes the Talos API (50000) and Kubernetes API (6443) in the
  Hetzner firewall  - both are reachable only over Tailscale
- Lets the `hcloud-talos` module render the Talos machineconfig with
  the Tailscale extension wired in, apply it to the node, and bootstrap
  etcd
- At first boot, `tailscaled` reads the auth key and joins the tailnet
  as `shire-control-plane-1`
- Outputs: `tunnel_token`, `public_ipv4`, `kubeconfig`, `talosconfig`
  (the kubeconfig and talosconfig are sensitive  - extract with
  `mise run tofu-output kubeconfig > kubeconfig`; kubectl reaches the
  API only over Tailscale because 6443 is firewalled)

### 4. `mise run tofu-secrets-sync`

Pipes the freshly-generated Cloudflare tunnel token through SOPS into
`clusters/shire/infrastructure/controllers/cloudflared-tunnel-token.sops.yaml`.
On every rebuild Cloudflare issues a fresh token, so the ciphertext
changes each rebuild  - review the diff, then commit and push:

```
git add clusters/shire/infrastructure/controllers/cloudflared-tunnel-token.sops.yaml
git commit -m "chore: tunnel token for fresh tunnel"
git push
```

This is the one bespoke step of the rebuild  - everything else is
idempotent.

### 5. `mise run flux-bootstrap`

Runs `flux bootstrap github` against this repo, pointing at
`clusters/shire`. Flux installs itself into the new cluster, creates
its own GitHub deploy key, and commits `clusters/shire/flux-system/`.

### 6. `mise run cluster-seed-sops-age`

Unwraps `bootstrap/cluster-age-key.sops.txt` (YubiKey touch) and
installs it as the `sops-age` Secret in `flux-system`. This is the
bootstrap's only chicken-and-egg  - every other piece of cluster state
is reconciled from git.

### 7. Flux reconciles `infrastructure/`

cloudflared, traefik, and local-path-provisioner come up as soon as
Flux can decrypt the tunnel-token Secret. Watch with:

```
flux get kustomizations --watch
```

~3 minutes from zero to ready.

### 8. Verify

- `tailscale status`  - `shire-control-plane-1` shows online in your tailnet
- `kubectl get nodes`  - resolves through Magic DNS over the tailnet
- `kubectl -n traefik get pods`  - Traefik pod is `Running`
- `curl -sI https://raveh.dev`  - returns `404 Not Found` served by
  Traefik through the tunnel. That proves DNS → Cloudflare edge →
  tunnel → Traefik end-to-end. No backend yet is expected at v1.

---

## What makes the rebuild fast

Everything decrypt-then-apply happens locally on your laptop with the
YubiKey present. No interactive clicks in cloud UIs beyond the one-time
bucket/project creation. No manual secret entry  - every secret that
tofu doesn't generate itself is already committed as ciphertext. The
only cluster state that isn't in git is the `sops-age` Secret in
step 6, and that's unwrapped from `bootstrap/cluster-age-key.sops.txt`
which *is* in git.
