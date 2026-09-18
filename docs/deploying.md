# Deploying

Cluster commands need [WireGuard access](setup.md#connect-to-the-existing-cluster).
OpenTofu commands need a YubiKey to decrypt provider credentials.

## Change Kubernetes resources

Edit manifests under `clusters/shire/`, add new files to the directory's
`kustomization.yaml`, and merge to `main`. Flux applies controllers first,
then their configuration and applications.

Put controllers in `infrastructure/controllers/`, resources that depend on
their CRDs in `infrastructure/configs/`, and applications in `apps/`.

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

`apply` produces another plan and asks for confirmation. Commit configuration
changes through a PR; merging does not run OpenTofu. For server replacement,
merge the configuration first and use
[rebuild](setup.md#rebuild-the-cluster), which requires a clean `main` checkout.

## Upgrade Talos or Kubernetes

Change the versions in [locals.tf](../tofu/locals.tf). Check the target release's
[upgrade instructions](https://docs.siderolabs.com/talos/v1.12/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
and [support matrix](https://docs.siderolabs.com/talos/v1.12/getting-started/support-matrix),
then use the OpenTofu commands above. The plan determines whether the server
will be replaced.

Keep `kubectl` in [mise.toml](../mise.toml) within one minor version of the
cluster, as required by the [Kubernetes version policy](https://kubernetes.io/releases/version-skew-policy/#kubectl).

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

[CI](../.github/workflows/ci.yaml) runs lint, secret scans and docs checks on every
PR and push to `main`. [Changed paths](../.github/ci-paths.yaml) select shell,
OpenTofu, manifest and recovery jobs. CI or shared tool changes run all jobs.
The required `checks` job fails if any selected job fails or is skipped.
No cloud credentials or YubiKey are needed.

| Check | What it verifies |
|---|---|
| Prek and Betterleaks | Formatting, shell/workflow lint, SOPS markers and secret scans |
| Bats | Real SOPS round trips, credential boundaries, parser compatibility and failure handling |
| OpenTofu | Backend-free validation and mocked backup-retention plans |
| Flate and Flux Schema | Flux/Helm rendering, schemas and CEL rules for pinned Kubernetes, Flux, Talos and chart versions; missing schemas fail |
| Docs | Local links and anchors, shell syntax and mise task names |

Use `tofu -chdir=tofu fmt -recursive` to fix formatting. Review rendered changes
with `mise run manifests:diff -- origin/main`; CI puts the diff in its job summary.
Secrets are omitted from the diff. Rendering substitutes encrypted values, so it
does not prove decryption or live authentication works.

### Recovery tests

```bash
mise run test:integration
```

Requires Docker and OpenSSL; downloads container images. It creates and deletes its own
Kind cluster, kubeconfig, age keys and S3 fixture. Flux must reject a wrong age key,
then decrypt after the correct key is restored. CNPG/Barman must restore fixture
rows. Restic runs backup and retention commands, then restores deleted files.
Operator charts, the Barman manifest and backup commands come from
`clusters/shire/`. Changes to these inputs or the test suite run
[recovery in CI](../.github/workflows/recovery-test.yaml) automatically.
Manual dispatch remains available.

Kind uses Kubernetes 1.35.8, the same minor as production. Local S3 and storage
replace Hetzner; a Bucket source replaces GitHub App authentication. These tests
do not cover production data, PITR, Hetzner CSI, WireGuard or Talos rebuilds.
Run [real recovery drills](disaster-recovery.md) separately with the YubiKey.

## Update vendored manifests

Replace [Barman's manifest](../clusters/shire/infrastructure/controllers/barman-cloud-plugin/manifest.yaml)
with the desired upstream release and update its source URL in the adjacent
`kustomization.yaml`. The URL is a source reference; the local manifest is what
Flux applies.
