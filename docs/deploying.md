# Deploy changes

Run these commands from the repository root after
[workstation setup](setup.md#set-up-a-workstation). Cluster commands require
the WireGuard connection; OpenTofu tasks decrypt credentials with a YubiKey.

## Change Kubernetes resources

Flux reads the branch configured in
[gotk-sync.yaml](../clusters/shire/flux-system/gotk-sync.yaml).
It reconciles controllers, then their dependent configuration and applications.

1. Edit the resource under `clusters/shire/` and include new files in the
   directory's `kustomization.yaml`. Use [SOPS](secrets.md#edit-a-secret) for secrets.
2. Run `mise run check`, review the diff, and merge the change into the branch
   Flux watches.
3. Request reconciliation and check readiness:

   ```bash
   mise run reconcile
   flux get kustomizations -A
   flux get helmreleases -A
   ```

A successful deployment has `Ready=True` for the affected resources. Check
the application itself as well. For failures, use
[Flux troubleshooting](troubleshooting.md#flux-is-not-reconciling).

To roll back a manifest change, revert its Git commit and merge the revert.
Flux will reconcile it. Database migrations and data changes need their own
recovery procedure; reverting a manifest does not undo them.

## Change cloud infrastructure

OpenTofu manages `tofu/`. Flux does not apply these files.

1. Edit the relevant configuration and run the checks.
2. Review a plan:

   ```bash
   mise run tofu:plan
   ```

3. For a change that does not require server replacement, run:

   ```bash
   mise run tofu:apply
   ```

   Review the plan shown by `apply` before confirming. DNS, firewall and
   routing changes can interrupt access even when no resource is replaced.
4. Verify the affected service and commit the configuration through the
   repository's review workflow.

If the plan replaces the server, first check the backups and choose the
[recovery procedure](disaster-recovery.md) for its data. Merge the intended
configuration and follow [cluster rebuild](setup.md#rebuild-the-cluster),
which requires a clean checkout of the branch Flux watches.

Reverting an OpenTofu file requires another plan and apply. It does not
recover a deleted resource's data.

## Upgrade Talos or Kubernetes

Version inputs are in [tofu/locals.tf](../tofu/locals.tf); the module and
machine configuration are in [tofu/main.tf](../tofu/main.tf). Check the target
release's [Talos upgrade instructions](https://docs.siderolabs.com/talos/v1.12/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
and [support matrix](https://docs.siderolabs.com/talos/v1.12/getting-started/support-matrix)
before changing them.

Run `mise run tofu:plan` to determine whether the change updates configuration
or replaces resources. A patch or minor version number alone does not establish
the disruption. Use the infrastructure workflow above, then verify:

```bash
talosctl version
kubectl get nodes -o wide
flux get kustomizations -A
```

## Application version updates

Wanderbound's Flux image automation writes updates to the
`flux-image-automation` branch. The
[GitHub workflow](../.github/workflows/flux-image-auto-pr.yaml) opens a PR
and enables automatic squash merge. The desired chart version is stored in
[app-chart.yaml](../clusters/shire/apps/wanderbound/app-chart.yaml).

To stop an unwanted update, suspend the automation and inspect any open PR
from that branch. For the rollback commands, see
[application rollback](disaster-recovery.md#roll-back-an-application-release).

## Refresh generated credentials

These tasks regenerate encrypted manifests in the working tree:

| Task | Credential |
|---|---|
| `mise run tunnel:refresh` | Cloudflare Tunnel token |
| `mise run hcloud-csi:refresh-token` | Hetzner CSI API token |
| `mise run tailscale-operator:refresh-oauth` | Tailscale operator OAuth credentials |

Review the encrypted diff, run the checks, then commit and merge it so Flux
can deliver the new value. These tasks do not commit or push. `rebuild` does
commit and push the Tunnel token as part of its procedure.

## Validation

```bash
mise run check
```

The task runs prek hooks, a Betterleaks history scan, Bats tests, and OpenTofu
validation. OpenTofu validation uses a temporary data directory with the
backend disabled and placeholder credentials; it does not decrypt secrets or
read remote state. A plan requires live credentials and remains an operator task.

The [CI workflow](../.github/workflows/ci.yaml) runs the same checks and skips
changes limited to Markdown and `docs/`. For documentation changes, check
links and command examples against the referenced scripts.
