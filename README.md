# infra

My personal infrastructure for [raveh.dev](https://raveh.dev).

## Architecture

- **Compute**  - Hetzner Cloud ARM server, provisioned with [OpenTofu](https://opentofu.org)
- **Platform**  - [Dokploy](https://dokploy.com), installed via cloud-init on first boot
- **Reverse proxy**  - Traefik, managed by Dokploy, auto-discovers containers
- **Ingress**  - Cloudflare Tunnel  - outbound-only, no public ports open on the server
- **DNS/TLS**  - Cloudflare-proxied wildcard DNS, managed by OpenTofu
- **Admin access**  - Dokploy panel gated by Cloudflare Access (identity-based SSO)
- **Storage**  - Persistent Hetzner volume, survives server rebuilds
- **State**  - OpenTofu remote state in Hetzner Object Storage (S3-compatible), client-side encrypted

## Setup

See [docs/setup.md](docs/setup.md).
