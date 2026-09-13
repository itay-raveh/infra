# Deploying

Cluster commands need [WireGuard access](setup.md#connect-to-the-existing-cluster).
OpenTofu commands need a YubiKey to decrypt provider credentials.

## Change Kubernetes resources

Edit manifests under `clusters/shire/`, add new files to the directory's
`kustomization.yaml`, and merge to `main`. Flux applies controllers first,
then their configuration and applications.

To pull the change immediately:

```bash
mise run reconcile
flux get kustomizations -A
flux get helmreleases -A
```

Affected resources should report `Ready=True`. For failures, see
[Flux troubleshooting](troubleshooting.md#flux-is-not-reconciling).
Revert the Git commit to roll back a manifest change. Database migrations
need a separate rollback.

## Change cloud infrastructure

Edit `tofu/`, then review the plan:

```bash
mise run tofu:plan
```

For a change that keeps the server:

```bash
mise run tofu:apply
```

`apply` produces another plan and asks for confirmation. Commit the configuration
after the apply. For server replacement, merge the configuration first and use
[rebuild](setup.md#rebuild-the-cluster), which requires a clean `main` checkout.

## Upgrade Talos or Kubernetes

Change the versions in [locals.tf](../tofu/locals.tf). Check the target release's
[upgrade instructions](https://docs.siderolabs.com/talos/v1.12/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
and [support matrix](https://docs.siderolabs.com/talos/v1.12/getting-started/support-matrix),
then use the OpenTofu commands above. The plan determines whether the server
will be replaced.

```bash
talosctl version
kubectl get nodes -o wide
```

## Application version updates

Flux writes Wanderbound chart updates to `flux-image-automation`. The
[GitHub workflow](../.github/workflows/flux-image-auto-pr.yaml) opens a PR and
enables automatic squash merge. Versions are in
[app-chart.yaml](../clusters/shire/apps/wanderbound/app-chart.yaml).
See [rollback](disaster-recovery.md#roll-back-an-application-release) to pin an
older release and pause updates.

## Refresh generated credentials

| Command | Kubernetes Secret |
|---|---|
| `mise run tunnel:refresh` | Cloudflare Tunnel token |
| `mise run hcloud-csi:refresh-token` | Hetzner CSI token |
| `mise run tailscale-operator:refresh-oauth` | Tailscale operator OAuth credentials |

Commit the generated `.sops.yaml` changes so Flux can load them. These commands
only write files; `rebuild` also commits and pushes the Tunnel token.
Refresh tasks keep the previous ciphertext when token generation or encryption
fails. See [secret storage and rotation](secrets.md).

## Checks

```bash
mise run check
```

Runs prek hooks, the Betterleaks history scan, Bats tests and OpenTofu validation.
Validation uses a temporary data directory with the backend disabled and needs
no cloud credentials. [CI](../.github/workflows/ci.yaml) runs the same checks;
Markdown-only changes skip CI.
