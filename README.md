# frodo  - personal infrastructure

GitOps-managed personal infrastructure for `raveh.dev`. Everything sensitive is SOPS-encrypted to YubiKey recipients; the repo is safe to make public at any commit.

**Architecture:** Hetzner Cloud (CAX21) → Talos Linux + Flux CD → Cloudflare Tunnel → `*.raveh.dev`

## Repo layout

See [docs/design.md §4](docs/design.md) for the full annotated tree. The three top-level planes are:

- `tofu/`  - OpenTofu: Hetzner server, volume, Cloudflare tunnel and DNS
- `talos/`  - talhelper input: machineconfig for the Talos node
- `clusters/frodo/`  - Flux manifests: in-cluster state (Helm releases, SOPS secrets)

## Getting started

See [docs/setup.md](docs/setup.md) for first-time bootstrap and laptop prerequisites.
