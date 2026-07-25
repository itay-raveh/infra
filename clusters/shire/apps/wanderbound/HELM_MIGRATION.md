# Wanderbound Helm ownership migration

Use this procedure when the matching Wanderbound image and chart version are
already published. The chart release must be named `wanderbound` in the
`wanderbound` namespace so its resource names and immutable selectors match the
current workload.

Do not continue if any preflight value differs from the expected live workload.
Do not merge the manifest change before adding the ownership and prune
annotations below.

From an unauthenticated shell, confirm that the exact chart can be pulled:

```bash
WANDERBOUND_VERSION='<VERSION_FROM_APP_CHART_YAML>'
helm show chart oci://ghcr.io/itay-raveh/charts/wanderbound \
  --version "$WANDERBOUND_VERSION"
```

## 1. Record the live workload

Save the output outside the repository so it can be compared after the handoff.

```bash
kubectl get persistentvolumeclaim wanderbound-app-data \
  --namespace wanderbound \
  --output=jsonpath='{.metadata.uid}{"\t"}{.spec.volumeName}{"\t"}{.status.capacity.storage}{"\n"}'
kubectl get deployment wanderbound \
  --namespace wanderbound \
  --output=jsonpath='{.spec.template.spec.containers[?(@.name=="app")].image}{"\n"}'
kubectl get configmap/wanderbound-config deployment/wanderbound \
  service/wanderbound persistentvolumeclaim/wanderbound-app-data \
  --namespace wanderbound
```

Confirm that the PVC is bound, its capacity is `50Gi`, and the current image tag
matches the chart version in `app-chart.yaml`.

## 2. Prepare Helm ownership and protect Flux pruning

```bash
kubectl label --namespace wanderbound \
  configmap/wanderbound-config deployment/wanderbound service/wanderbound \
  persistentvolumeclaim/wanderbound-app-data \
  app.kubernetes.io/managed-by=Helm --overwrite

kubectl annotate --namespace wanderbound \
  configmap/wanderbound-config deployment/wanderbound service/wanderbound \
  persistentvolumeclaim/wanderbound-app-data \
  meta.helm.sh/release-name=wanderbound \
  meta.helm.sh/release-namespace=wanderbound \
  kustomize.toolkit.fluxcd.io/prune=disabled \
  --overwrite
```

Inspect all four resources and verify the new metadata before merging. If the
handoff is stopped here, remove the added label and annotations and leave the
raw manifests in Git.

## 3. Reconcile the chart release

Merge the manifest change only after the preparation step succeeds, then run:

```bash
mise run reconcile
mise run flux:sync-ks -- --namespace flux-system apps
flux reconcile source oci wanderbound-chart --namespace wanderbound
mise run flux:sync-hr -- --namespace wanderbound wanderbound
flux get source oci wanderbound-chart --namespace wanderbound
flux get helmrelease wanderbound --namespace wanderbound
kubectl rollout status deployment/wanderbound --namespace wanderbound
```

Do not continue until the OCIRepository and HelmRelease are ready and the
Deployment rollout succeeds. If the release has not installed, revert the Git
change, reconcile `apps`, and confirm that the protected raw resources remain.
If Helm has installed any release revision, stop and plan the reverse ownership
handoff. Deleting the HelmRelease and restoring raw manifests in one reconcile
can delete application resources.

## 4. Verify identity and finish the handoff

Run the preflight PVC command again. Its `uid` and `volumeName` must exactly
match the recorded values, its capacity must remain `50Gi`, and the Deployment
must use the intended release image.

Confirm that the Flux Kustomization inventory no longer owns the four workload
resources:

```bash
flux tree kustomization apps --namespace flux-system
```

After every check succeeds, remove the temporary prune protection. Helm
ownership metadata stays in place.

```bash
kubectl annotate --namespace wanderbound \
  configmap/wanderbound-config deployment/wanderbound service/wanderbound \
  persistentvolumeclaim/wanderbound-app-data \
  kustomize.toolkit.fluxcd.io/prune-
```
