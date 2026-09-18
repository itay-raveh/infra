# Deploying

Kubernetes commands require [WireGuard](setup.md#connect-to-the-existing-cluster). OpenTofu requires a YubiKey.

## Kubernetes resources

| Resource | Location |
|---|---|
| Controllers and operators | `clusters/shire/infrastructure/controllers/` |
| Shared resources requiring those CRDs | `clusters/shire/infrastructure/configs/` |
| Application resources and environment values | `clusters/shire/apps/<APP>/` |

Register manifests in the owning `kustomization.yaml`. Review and merge a PR to `main`; Flux reconciles dependencies before their consumers.

```bash
mise run reconcile
flux get kustomizations -A
flux get helmreleases -A
```

Expected: `Ready=True` for active resources. See [troubleshooting](troubleshooting.md#flux-is-not-reconciling) for failures.

## Cloud resources

```bash
mise run tofu:plan
mise run tofu:apply
```

`apply` presents a fresh plan for approval. Merging a PR does not run OpenTofu. For server replacement, merge first and follow [rebuild](setup.md#rebuild-the-cluster).

Talos and Kubernetes versions live in [locals.tf](../tofu/locals.tf). Check the target [Talos upgrade instructions](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/lifecycle-management/upgrading-talos); keep `kubectl` within [one minor version](https://kubernetes.io/releases/version-skew-policy/#kubectl) of the API server.

## Application releases

Each application's manifests select its artifact and supply environment values and Secret references. Image automation writes updates to `flux-image-automation`; the [shared workflow](../.github/workflows/flux-image-auto-pr.yaml) opens a PR and enables automatic squash merge.

To pin or roll back a release:

1. Suspend its `ImageUpdateAutomation` and check for an already-open update PR.
2. Change the selected version or digest in the application's manifests.
3. Review and merge the change. Check the application's health after reconciliation.

```bash
flux suspend image update '<AUTOMATION>' -n flux-system
flux resume image update '<AUTOMATION>' -n flux-system
```

Manifest rollback does not undo database migrations. Follow the application's migration compatibility requirements.

## Validation

```bash
mise run check
mise run manifests:diff -- origin/main
mise run test:integration
```

| Check | Coverage |
|---|---|
| Lint | Formatting, shell/workflow syntax, secret scanning and documentation links |
| Bats | Credential handling, file replacement and infrastructure scripts |
| OpenTofu | Backend-free validation and mocked plans |
| Manifest rendering | Flux/Helm output and CRD schemas; not live authentication or custom health-expression evaluation |
| Integration | Flux/SOPS decryption, CNPG/Barman restore and restic restore in a disposable Kind cluster |

Integration tests require Docker and OpenSSL. They use fixture data and local S3, not production credentials, Hetzner CSI or Talos recovery. [CI path filters](../.github/ci-paths.yaml) select affected checks; its required `checks` job rejects selected jobs that fail or skip.

## Vendored manifests

For [Barman](../clusters/shire/infrastructure/controllers/barman-cloud-plugin/), update both `manifest.yaml` and the upstream source URL in `kustomization.yaml`.
