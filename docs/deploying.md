# Deploying

Day-to-day workflows for changing what's running on the cluster. Three
classes of change, each with its own loop:

1. **Cluster state changes** (Helm releases, Kubernetes manifests,
   secrets)  - Flux pulls them on its own.
2. **Infrastructure changes** (server type, DNS, tunnel config)  -
   `mise run tofu-apply` from your laptop.
3. **Talos / Kubernetes upgrades**  - bump the locals in `tofu/locals.tf`,
   then `tofu-apply`.

Everything below assumes you've completed the one-time setup in
`setup.md` and have a YubiKey plugged in.

---

## 1. Cluster state changes (the common case)

The Flux loop is: edit → commit → push → wait. Flux polls this repo
every minute and reconciles `clusters/shire/infrastructure/` against
the live cluster.

All HelmReleases and SOPS-encrypted Secrets follow the existing
patterns in `clusters/shire/infrastructure/controllers/`. Add new
resources to the directory's `kustomization.yaml`.

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
2. `mise run tofu-plan`  - review the diff. The task unwraps the state
   passphrase from SOPS (one YubiKey touch); the `sops` Terraform
   provider reads the Tailscale auth key during plan (second touch).
3. `mise run tofu-apply`  - same dance, then apply. Targeted changes
   (firewall rules, DNS records, Cloudflare tunnel config) are
   non-disruptive. Server-replacement changes (server type bump,
   image swap) destroy and recreate the node  - see "Replacing the
   server" below.
4. Commit and push the `.tf` change.

### Replacing the server (server type bump, image swap, etc.)

The node is cattle. All persistent data lives in S3 backups (CNPG PITR
for Postgres, tarballs for app data, etcd snapshots for cluster state).

1. Edit `tofu/locals.tf` (or wherever the change lives).
2. `tofu-apply`. The hcloud-talos module destroys the old server,
   creates a new one, and applies the same machineconfig.
3. Cluster downtime: ~5 minutes. Single-node, no HA  - accept it or
   schedule it.
4. If the server is fully replaced, use `mise run rebuild` which
   handles the tunnel token, Flux bootstrap, and SOPS key seeding.
5. The cluster's PKI lives in tofu state, so the new server boots into
   the same Kubernetes cluster identity.
6. Restore stateful data from S3 if needed (see `disaster-recovery.md`).

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
