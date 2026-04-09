# infra

My personal infrastructure for [raveh.dev](https://raveh.dev). One `tofu apply` provisions a Hetzner Cloud ARM server with [Dokploy](https://dokploy.com/)  - a self-hosted PaaS that manages Docker, Traefik, and TLS so I can deploy projects with just a Git push.

## Architecture

- **Compute**  - Hetzner Cloud ARM server, provisioned with [OpenTofu](https://opentofu.org/)
- **Platform**  - [Dokploy](https://dokploy.com/), installed via cloud-init on first boot
- **Reverse proxy**  - Traefik, managed by Dokploy, auto-discovers containers
- **DNS/TLS**  - Cloudflare-proxied wildcard DNS, managed by OpenTofu
- **Storage**  - Persistent Hetzner volume, survives server rebuilds
- **State**  - OpenTofu remote state in Hetzner Object Storage (S3-compatible)
- **Admin access**  - SSH tunnel only, panel not publicly exposed

## Setup

See [docs/setup.md](docs/setup.md).
