# shire — personal infrastructure

GitOps-managed personal infrastructure for `raveh.dev`. Everything sensitive is SOPS-encrypted to YubiKey recipients; the repo is safe to make public at any commit.

**Architecture:** Hetzner Cloud (CAX21) → Talos Linux + Flux CD → Cloudflare Tunnel → `*.raveh.dev`

## Repo layout

Three top-level planes, each with one owner:

- `tofu/` — OpenTofu: Hetzner server, volume, Cloudflare tunnel and DNS
- `talos/` — SOPS-encrypted Tailscale auth key (Talos machineconfig is rendered by the hcloud-talos tofu module)
- `clusters/shire/` — Flux manifests: in-cluster state (HelmReleases, SOPS-encrypted secrets)

## Getting started

See [docs/setup.md](docs/setup.md) for first-time bootstrap and laptop prerequisites.
