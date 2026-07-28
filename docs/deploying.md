# Deploying

Day-to-day workflows for changing what's running on the cluster. Three
classes of change, each with its own loop:

1. **Cluster state changes** (Helm releases, Kubernetes manifests,
   secrets)  - Flux pulls them on its own.
2. **Infrastructure changes** (server type, DNS, tunnel config)  -
   `mise run tofu:apply` from your laptop.
3. **Talos / Kubernetes upgrades**  - bump the locals in `tofu/locals.tf`,
   then `tofu:apply`.

Everything below assumes you've completed the one-time setup in
`setup.md`, have a YubiKey plugged in, and have the `shire` WireGuard
interface active. Run `mise run wireguard:configure` if needed.

---

## 1. Cluster state changes (the common case)

The Flux loop is: edit → commit → push → wait. Flux polls this repo
every minute and reconciles infrastructure controllers, dependent
infrastructure configuration, and applications against the live cluster.

Cluster-wide controllers and their Secrets live in
`clusters/shire/infrastructure/controllers/`. Configuration that depends
on their CRDs lives in `clusters/shire/infrastructure/configs/`.
Application releases and Secrets live under `clusters/shire/apps/`.
Add each resource to the `kustomization.yaml` in the matching directory.

SOPS files must use the `.sops.yaml` suffix. The pre-commit hook
refuses to commit without `ENC[` markers. Edit existing ones with
`sops <file>` (decrypts in `$EDITOR`, re-encrypts on save).

Rollback: `git revert <bad-commit> && git push`. To pause Flux while
debugging: `flux suspend kustomization infrastructure`.

---

## 2. Infrastructure changes (rarer)

Anything in `tofu/` is operator-driven, not Flux-driven.

### Changing server, DNS, tunnel config

1. Edit the relevant `.tf` file.
2. `mise run tofu:plan`  - review the diff. The task unwraps the state
   passphrase and provider credentials from the single SOPS file with
   one YubiKey touch during its cached authorization window.
3. `mise run tofu:apply`  - decrypts the same file, then applies.
   Targeted changes (firewall rules, DNS records, Cloudflare tunnel config) are
   non-disruptive. If the plan replaces the server, do not apply it here.
   Follow "Replacing the server" below so preflight runs before destruction.
4. Commit and push the `.tf` change.

### Replacing the server (server type bump, image swap, etc.)

The node is cattle. Live data uses node-local or Hetzner volumes, while
recoverable copies live in S3 backups (CNPG PITR for Postgres, tarballs
for app data, and etcd snapshots for cluster state).

1. Edit the relevant OpenTofu configuration and run `mise run tofu:plan`.
2. Commit the desired state, merge it to `main`, and update the local
   `main` branch. The rebuild preflight requires a clean `main` tracking
   `origin/main`, because Flux reconciles that branch.
3. Run `mise run rebuild`. Its doctor preflight completes before any apply.
   The hcloud-talos module then replaces the server and delivers the
   WireGuard machine configuration before private API bootstrap begins.
4. Expect about 15 minutes of downtime. The cluster PKI lives in OpenTofu
   state, so the replacement boots into the same Kubernetes identity.
5. Restore stateful data from S3 if needed (see `disaster-recovery.md`).

---

## 3. Talos / Kubernetes upgrades

Both versions are pinned in `tofu/locals.tf`:

```hcl
talos_version      = "v1.12.8"
kubernetes_version = "v1.35.2"
```

To upgrade:

1. Pick a target version. Read the Talos release notes and the matching
   Kubernetes upgrade notes.
2. Bump the local. For Talos minor bumps, also re-render the schematic -
   `tofu:apply` re-fetches the Image Factory schematic for the new
   version automatically because `data.talos_image_factory_extensions_versions.this`
   is keyed off `local.talos_version`.
3. `mise run tofu:plan`. Review what gets replaced. Talos minor upgrades
   typically replace the snapshot and reboot the node (~5 minutes
   downtime). Patch upgrades do an in-place reconfigure with no reboot.
4. `mise run tofu:apply`.
5. Verify with `kubectl get nodes` and `talosctl version`.

---

## Pre-commit and CI

See `.pre-commit-config.yaml` and `.github/workflows/` for the full
hook and CI job list. Key non-obvious detail: `tofu plan` does **not**
run in CI - it needs the state encryption passphrase and live cloud
credentials, both of which are operator-local and never touch a runner.

---

## Common gotchas

- **Editing a `.sops.yaml` file with a regular editor.** Don't -
  `sops <file>` opens it decrypted in `$EDITOR`. Saving with vim/code
  directly will produce encrypted-looking gibberish that won't decrypt.
- **Tunnel token after rebuild.** `mise run rebuild` handles the
  commit+push automatically. If you're doing a partial rebuild, the
  tunnel token must land in git before Flux can reconcile cloudflared.
- **Touching `clusters/shire/flux-system/`.** Flux owns that directory.
  If `flux bootstrap` regenerates it, hand-edits get clobbered.
- **YubiKey touch timeouts.** Touch policy is `cached` (~15s window),
  so multiple decryptions in quick succession only need one touch.
  If you're slow, you'll get a second prompt.
