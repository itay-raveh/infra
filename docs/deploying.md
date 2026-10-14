# Deploying

Kubernetes commands require [WireGuard](setup.md#connect-to-the-existing-cluster). OpenTofu requires a YubiKey.

## Kubernetes resources

| Resource | Location |
|---|---|
| Controllers and operators | `clusters/shire/infrastructure/controllers/` |
| Shared resources requiring those CRDs | `clusters/shire/infrastructure/configs/` |
| Application resources and environment values | `clusters/shire/apps/<APP>/` |

Register manifests in the owning `kustomization.yaml`. `main` requires a PR, passing `checks` from GitHub Actions and squash merge. Flux verifies the resulting commit with the GitHub signing key before reconciling dependencies and consumers.

The public key is in [flux-system/](../clusters/shire/flux-system/). It authenticates GitHub's merge signature, not the PR author's identity. When GitHub rotates its [signing key](https://github.com/web-flow.gpg), verify the replacement and apply that directory with `kubectl apply -k clusters/shire/flux-system` before reconciling.

Apply repository rules with `bash scripts/configure-github.sh`. Flux authenticates the infra Git source with the encrypted GitHub App Secret.

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

Application CI publishes OCI Helm charts containing the tested container image digest. Flux consumes those charts directly with [`HelmRelease.chartRef` and `OCIRepository.ref.semver`](https://fluxcd.io/flux/components/helm/helmreleases/#recommended-settings). Infra PRs own environment values, Secret references and the allowed version range. Renovate owns third-party dependencies; its [package rules](../.github/renovate.json) exclude these two app charts so it cannot move a rollback digest pin.

| Application | OCI chart | Stable range | Version |
|---|---|---|---|
| Wanderbound | `ghcr.io/itay-raveh/charts/wanderbound` | `>=1.16.1`, including future majors | Release tag without `v`; earlier charts do not bundle image digests |
| Quizmon | `ghcr.io/itay-raveh/charts/quizmon` | `>=0.0.0`, including future majors | `0.<CI run number>.<run attempt>` for successful runtime or chart builds |

Both sources filter tags to numeric `major.minor.patch` versions. App publication validates chart schemas and rendered Kubernetes resources using the public infra production values before publishing the release chart. It records the infra revision used. Environment changes also require the normal infra validation gate. A passing chart render does not validate live Secret contents or credentials.

### Migration order (draft)

This sequence has not been exercised against production. The infra switch remains a draft until the first compatible charts exist and their public registry reads succeed. The migration takes effect when the infra PR is merged; no calendar cutoff is scheduled. The owner may classify this section as historical after both HelmReleases are ready on OCI charts.

| Current selection | OCI selection |
|---|---|
| Wanderbound image policy writes chart tags through Git PRs | Stable OCI chart versions starting at the first digest-bound release |
| Quizmon Git chart revision and independently selected image digest | One immutable OCI chart containing its tested image digest and templates |
| Shared updater workflow mints a GitHub App write token | Source controller reads OCI charts; infra Git source keeps its current App Secret |

1. Merge the app release-contract PRs after their checks pass. Undo: revert an app PR before publishing new releases; retain published artifacts for rollback.
2. Publish and verify a Wanderbound release at `1.16.1` or later and a Quizmon OCI chart through their normal CI. This is an operator release action, outside PR preparation. Verify that both packaged charts contain the expected image digest and render with production values. Artifact publication is retained in the registry; undo selection with a chart digest pin rather than deleting the artifact.
3. Review and merge the infra switch. Wrong order leaves a chart source without a matching artifact. Undo: revert the switch to restore the previous source and selected image, subject to database compatibility.
4. Verify source and HelmRelease readiness with the safe read-only commands below. Inspect failed release Jobs and application health before accepting the rollout.

```bash
flux get sources oci -A
flux get helmreleases -A
mise run flux:unhealthy
```

The unused image scanners, policies, automations and shared PR workflow are removed from Git. Fresh Flux installations omit the two image controllers. Existing controller deployments, the old Actions environment and its secrets, and GitHub App write permissions require a separately approved live cleanup after verification. Keep `flux-github-app`: the infra Git source still uses it. No permission reduction or live secret deletion happens through this change.

### Hold and rollback (draft)

These production procedures have not been exercised. The Git edits below are proposed through an infra PR and become production changes only when an operator merges it. Read-only inspection is safe at any time.

1. Choose a previously healthy chart's OCI manifest digest from the application publication summary or `HelmRelease.status.history[].ociDigest`. Confirm the digest belongs to the desired image and templates; keep registry history available.
2. Add `ref.digest: sha256:<KNOWN_CHART_DIGEST>` to the application's OCIRepository in Git. [`ref.digest` takes precedence over semver](https://fluxcd.io/flux/components/source/ocirepositories/#digest-example), so the pin holds against later publications. To stop all Helm actions immediately, an operator can suspend the HelmRelease; persist `spec.suspend: true` in Git for a durable stop.
3. Review and merge the pin, then inspect readiness and application health. A previously healthy chart may still be incompatible with the current database. Database migrations are not reversed automatically. Quizmon's Cloudflare Worker and Kubernetes resources are separate deployment planes; their rollback is not atomic, and versions must remain compatible.
4. Resume tracking only after the release is verified: remove `ref.digest` in a reviewed infra PR and remove any HelmRelease suspension. Undo: restore the digest pin and suspension.

Safe inspection:

```bash
kubectl -n wanderbound get helmrelease wanderbound -o jsonpath='{.status.history}'
kubectl -n quizmon get helmrelease quizmon -o jsonpath='{.status.history}'
flux get sources oci -A
flux get helmreleases -A
```

Operator-only immediate stop (writes to production, draft):

```bash
flux suspend helmrelease wanderbound -n wanderbound
flux suspend helmrelease quizmon -n quizmon
```

An imperative Helm rollback alone is undone by Flux reconciliation. Use the Git chart digest pin to hold the chosen release. Existing `flux:unhealthy`, HelmRelease conditions and release Job logs identify failed releases; [troubleshooting](troubleshooting.md#flux-is-not-reconciling) describes inspection and reset after the cause is fixed.

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
