# bootstrap/

Artifacts needed **before** Flux exists on a fresh cluster. Everything else in
this repo is reconciled by Flux; this directory is not.

## Contents

- `cluster-age.key.sops`  - the cluster software age key (what Flux's
  kustomize-controller uses in-cluster to decrypt `*.sops.yaml` files), itself
  encrypted to the two YubiKeys only. Generated once in `docs/design.md` §6.A
  step 6; unwrapped into a `sops-age` Secret in `flux-system` during §6.B step 6.

The cluster key is encrypted to YubiKeys only  - not to itself  - so the
`.sops.yaml` creation rule for this path deliberately excludes
`age1cluster...` from the recipient list.

## Rules

- **Read-only post-bootstrap.** Do not rotate files here from a running cluster.
  Rotation of the cluster software key is a full §6.A replay.
- **Not reconciled by Flux.** Nothing in this directory is a Kubernetes manifest.
- **No plaintext.** The only file that may ever live here is `cluster-age.key.sops`
  (ciphertext). The plaintext equivalent is generated in `/tmp`, used once, then
  `shred`ed per §6.A step 6.
