# Deploying

Day-to-day workflows for changing what's running on the cluster. Three
classes of change, each with its own loop:

1. **Cluster state changes** (Helm releases, Kubernetes manifests,
   secrets)  - Flux pulls them on its own.
2. **Infrastructure changes** (server type, DNS, tunnel config, volume
   size)  - `mise run tofu-apply` from your laptop.
3. **Talos / Kubernetes upgrades**  - bump the locals in `tofu/locals.tf`,
   then `tofu-apply`.

Everything below assumes you've completed the one-time setup in
`setup.md` and have a YubiKey plugged in.

---

## 1. Cluster state changes (the common case)

The Flux loop is: edit → commit → push → wait. Flux polls this repo
every minute and reconciles `clusters/frodo/infrastructure/` against
the live cluster.

### Bumping a Helm chart version

1. Edit `clusters/frodo/infrastructure/controllers/<chart>/release.yaml`
   and change `spec.chart.spec.version`.
2. Read the chart's release notes if it's a major bump. Adjust
   `spec.values` if anything became non-default.
3. Commit, push, wait. Watch with `flux get hr -A --watch`.
4. If the upgrade fails, Flux's `upgrade.remediation.retries: 3` rolls
   back automatically. The HelmRelease shows `False` and a reason in
   `kubectl describe hr -n <ns> <name>`.

### Adding a new HelmRelease

1. If the chart's source isn't already pulled, add a `HelmRepository`
   under `clusters/frodo/infrastructure/sources/` and reference it
   from `sources/kustomization.yaml`.
2. Create `clusters/frodo/infrastructure/controllers/<name>/release.yaml`.
3. Add the file path to `clusters/frodo/infrastructure/controllers/kustomization.yaml`.
4. Commit, push, wait.

### Adding a SOPS-encrypted Secret

The cluster can decrypt anything encrypted to the cluster software age
key. To add one:

1. Create the plaintext Secret manifest in your editor.
2. Save it under `clusters/frodo/...` with a `.sops.yaml` suffix
   (e.g. `my-app.sops.yaml`). The pre-commit hook refuses to commit
   the file without `ENC[` markers, so you cannot accidentally push
   plaintext.
3. `sops --encrypt --in-place clusters/frodo/.../my-app.sops.yaml`.
   YubiKey touch.
4. Commit, push.

To edit an existing one: `sops clusters/frodo/.../my-app.sops.yaml`
opens it decrypted in `$EDITOR`; saving re-encrypts to all configured
recipients automatically.

### Forcing a reconcile

Flux normally polls every minute. To kick it now:

```
flux reconcile source git flux-system
flux reconcile kustomization infrastructure
```

### Rolling back

Flux is git-driven, so the rollback is `git revert <bad-commit> &&
git push`. Wait for Flux to pull. If you need to halt reconciliation
while you debug, suspend the affected resource:

```
flux suspend kustomization infrastructure
# fix things
flux resume kustomization infrastructure
```

---

## 2. Infrastructure changes (rarer)

Anything in `tofu/` is operator-driven, not Flux-driven.

### Changing server, volume, DNS, tunnel config

1. Edit the relevant `.tf` file.
2. `mise run tofu-plan`  - review the diff. The task unwraps the state
   passphrase and Tailscale auth key from SOPS automatically; you'll
   touch the YubiKey twice.
3. `mise run tofu-apply`  - same dance, then apply. Targeted changes
   (firewall rules, DNS records, Cloudflare tunnel config) are
   non-disruptive. Server-replacement changes (server type bump,
   disk size, image swap) destroy and recreate the node  - see
   "Replacing the server" below.
4. Commit and push the `.tf` change.

### Replacing the server (CAX21 → bigger, image bump, etc.)

The node is cattle. The Hetzner Volume is the pet (`prevent_destroy`
in tofu protects it).

1. Edit `tofu/locals.tf` (or wherever the change lives).
2. `tofu-apply`. The hcloud-talos module destroys the old server,
   creates a new one, applies the same machineconfig, and re-attaches
   the volume. PVC data on the volume survives untouched.
3. Cluster downtime: ~5 minutes. Single-node, no HA  - accept it or
   schedule it.
4. If the rebuild produces a fresh Cloudflare tunnel token, run
   `mise run tofu-secrets-sync` and commit the new ciphertext.
5. The cluster's PKI lives in tofu state, so the new server boots into
   the same Kubernetes cluster identity. No `flux bootstrap` needed.

### Resizing the data volume

```
# 1. Edit tofu/main.tf, change hcloud_volume.data.size
# 2. mise run tofu-apply
# 3. The volume grows online. Resize the filesystem inside Talos:
talosctl --talosconfig=./talosconfig -n frodo \
  volumes mount filesystem-resize /var/mnt/data
```

(Verify the exact talosctl subcommand against your installed version
before running  - Talos volume management commands have changed across
minor versions.)

---

## 3. Talos / Kubernetes upgrades

Both versions are pinned in `tofu/locals.tf`:

```hcl
talos_version      = "v1.12.6"
kubernetes_version = "v1.35.2"
```

To upgrade:

1. Pick a target version. Read the Talos release notes and the matching
   Kubernetes upgrade notes.
2. Bump the local. For Talos minor bumps, also re-render the schematic -
   `tofu-apply` re-fetches the Image Factory schematic for the new
   version automatically because `data.talos_image_factory_extensions_versions.this`
   is keyed off `local.talos_version`.
3. `mise run tofu-plan`. Review what gets replaced. Talos minor upgrades
   typically replace the snapshot and reboot the node (~5 minutes
   downtime). Patch upgrades do an in-place reconfigure with no reboot.
4. `mise run tofu-apply`.
5. Verify with `kubectl get nodes` and `talosctl version`.

---

## Pre-commit and CI

The local pre-commit hooks run on every commit:

- `gitleaks`  - scans the diff for secret patterns
- `sops-verify`  - refuses to commit any `*.sops.*` file that isn't
  actually encrypted
- `tofu_fmt`  - formats `tofu/` in place
- `yamllint`  - lints YAML

CI on GitHub runs the same gitleaks scan plus three additional jobs
on every PR and push to `main`:

- `sops-sanity`  - repeats the encryption check across the whole tree
  and refuses any plaintext `kind: Secret` manifest under `clusters/`
- `flux-build`  - `flux build kustomization infrastructure --dry-run`
  catches malformed HelmRelease values, broken `dependsOn`, missing
  substitutions before they reach the cluster
- `tofu-validate`  - `tofu fmt -check -recursive` + `tofu validate`

All four are required green for a merge to `main`. Branch protection
disallows force-push and admin bypass.

`tofu plan` does **not** run in CI  - it needs the state encryption
passphrase and live cloud credentials, both of which are operator-local
and never touch a runner.

---

## Common gotchas

- **Editing a `.sops.yaml` file with a regular editor.** Don't -
  `sops <file>` opens it decrypted in `$EDITOR`. Saving with vim/code
  directly will produce encrypted-looking gibberish that won't decrypt.
- **Forgetting to commit a fresh tunnel token after rebuild.** Step 4
  of the every-rebuild path is the one bespoke step  - Flux can't
  reconcile cloudflared until it lands.
- **Touching `clusters/frodo/flux-system/`.** Flux owns that directory.
  If `flux bootstrap` regenerates it, hand-edits get clobbered.
- **YubiKey touch timeouts.** Touch policy is `cached` (~15s window),
  so multiple decryptions in quick succession only need one touch.
  If you're slow, you'll get a second prompt.
