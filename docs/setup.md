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
- **Hetzner Object Storage bucket** named `raveh-infra-tfstate` (in `hel1`),
  plus an S3 credential pair for it. This holds the encrypted tofu state.
- **Cloudflare account** with `raveh.dev` on it. Create an API token
  scoped to `Zone:DNS edit` + `Zero Trust edit` on that one zone.
- **GitHub account** (`itay-raveh`) and a local `gh auth login` session.
- **Tailscale account** with a tailnet, an ACL tag `tag:frodo` defined,
  and a reusable pre-auth key for that tag. 90-day expiry is fine because
  the key is captured in SOPS, not re-typed.

### 2. Laptop prerequisites

```
mise install        # reads .mise.toml and pulls every tool
pre-commit install  # activates the local hooks
```

### 3. Initialize both YubiKeys

Plug in primary:

```
age-plugin-yubikey --generate --slot 1 --touch-policy cached --pin-policy once
```

Record the public key (`age1yubikey1...`). Repeat with the backup
YubiKey, in a separate slot. **Store one YubiKey offsite** as soon as
you've recorded both public keys.

### 4. Generate the cluster software age key

```
age-keygen -o /tmp/cluster.key
```

This is the key Flux's kustomize-controller uses inside the cluster to
decrypt `*.sops.yaml` files. It exists in plaintext for about 30 seconds.

### 5. Write `.sops.yaml`

Substitute the placeholders with the three real public keys (both
YubiKeys + the cluster software key from step 4). Verify the
`creation_rules:` paths still match the repo layout.

### 6. Encrypt the cluster software key to YubiKeys only

```
sops --encrypt --age <yubikey1>,<yubikey2> /tmp/cluster.key \
  > bootstrap/cluster-age.key.sops
shred -u /tmp/cluster.key
```

The cluster key cannot decrypt itself, so the `.sops.yaml` rule for
`bootstrap/cluster-age.key.sops` deliberately excludes it from the
recipient list  - only the two YubiKeys can read this file.

### 7. Encrypt the state passphrase

```
openssl rand -base64 48 \
  | sops --encrypt --input-type binary /dev/stdin \
  > tofu/encryption-passphrase.sops.txt
```

YubiKey touch. This is the passphrase that AES-GCM-encrypts the tofu
state file in the S3 backend bucket.

### 8. Encrypt the Tailscale auth key

Generate a reusable pre-auth key for `tag:frodo` in the Tailscale admin
console, then:

```
printf '%s' 'tskey-auth-<redacted>' \
  | sops --encrypt --input-type binary /dev/stdin \
  > talos/tailscale-authkey.sops.txt
```

The `mise run tofu-apply` task decrypts this on each rebuild and exports
it as `TF_VAR_tailscale_auth_key`. The key never lands on disk in
plaintext after this step.

### 9. Apply branch protection on `main`

```
mise run branch-protect
```

Posts the rules in `scripts/branch-protection.json` to the GitHub API.
One-shot; re-run any time to reassert the rules.

### 10. Commit everything

At this point `bootstrap/cluster-age.key.sops`, `.sops.yaml`,
`tofu/encryption-passphrase.sops.txt`, `talos/tailscale-authkey.sops.txt`,
and `.env.example` are all in git. Commit and push them. The repo is
now self-bootstrapping.

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
- `TF_VAR_ssh_public_key_path`  - absolute path to your SSH public key
  (used only by Hetzner rescue mode break-glass; Talos itself does not
  use SSH)
- `SOPS_AGE_KEY_FILE`  - path to your age-plugin-yubikey identity stub

Then `gh auth login` so `flux bootstrap github` (step 5) can read
`GITHUB_TOKEN` via `gh auth token`.

### 3. `mise run tofu-apply`

The task unwraps the state passphrase from
`tofu/encryption-passphrase.sops.txt` and the Tailscale auth key from
`talos/tailscale-authkey.sops.txt` (one YubiKey touch each), exports
them, then runs `tofu apply`. That:

- Builds the custom Talos schematic at the Image Factory (extensions
  baked in: `siderolabs/hcloud`, `qemu-guest-agent`, `tailscale`)
- Uploads the resulting `hcloud-arm64.raw.xz` into Hetzner as a snapshot
  via the `imager` provider
- Creates a CAX21 ARM server from that snapshot in `hel1`
- Creates the persistent `frodo-data` Hetzner Volume and attaches it
- Closes the Talos API (50000) and Kubernetes API (6443) in the
  Hetzner firewall  - both are reachable only over Tailscale
- Lets the `hcloud-talos` module render the Talos machineconfig with
  the Tailscale extension wired in, apply it to the node, and bootstrap
  etcd
- At first boot, `tailscaled` reads the auth key and joins the tailnet
  as `frodo`
- Writes a local kubeconfig (kubectl reaches the API only over the
  tailnet because 6443 is firewalled)
- Outputs: `tunnel_token`, `frodo_public_ipv4`, `kubeconfig`,
  `talosconfig`

### 4. `mise run tofu-secrets-sync`

Pipes the freshly-generated Cloudflare tunnel token through SOPS into
`clusters/frodo/infrastructure/controllers/cloudflared/tunnel-token.sops.yaml`.
On every rebuild Cloudflare issues a fresh token, so the ciphertext
changes each rebuild  - review the diff, then commit and push:

```
git add clusters/frodo/infrastructure/controllers/cloudflared/tunnel-token.sops.yaml
git commit -m "chore: tunnel token for fresh tunnel"
git push
```

This is the one bespoke step of the rebuild  - everything else is
idempotent.

### 5. `mise run flux-bootstrap`

Runs `flux bootstrap github` against this repo, pointing at
`clusters/frodo`. Flux installs itself into the new cluster, creates
its own GitHub deploy key, and commits `clusters/frodo/flux-system/`.

### 6. Install the `sops-age` secret

This is the only piece of cluster state that can't be reconciled from
git directly  - it's the key Flux *needs* in order to reconcile
encrypted manifests:

```
sops --decrypt bootstrap/cluster-age.key.sops \
  | kubectl create secret generic sops-age \
      -n flux-system \
      --from-file=age.agekey=/dev/stdin
```

YubiKey touch. This is the bootstrap's only chicken-and-egg.

### 7. Flux reconciles `infrastructure/`

cloudflared, traefik, and local-path-provisioner come up as soon as
Flux can decrypt the tunnel-token Secret. Watch with:

```
flux get kustomizations --watch
```

~3 minutes from zero to ready.

### 8. Verify

- `tailscale status`  - `frodo` shows online in your tailnet
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
step 6, and that's unwrapped from `bootstrap/cluster-age.key.sops`
which *is* in git.
