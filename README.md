# Personal infrastructure

[![CI](https://github.com/itay-raveh/infra/actions/workflows/ci.yaml/badge.svg)](https://github.com/itay-raveh/infra/actions/workflows/ci.yaml)
[![License](https://img.shields.io/github/license/itay-raveh/infra)](https://github.com/itay-raveh/infra/blob/main/LICENSE)

GitOps-managed personal infrastructure for `raveh.dev`.

## Architecture

```mermaid
graph TD
    Internet -->|HTTPS| CF[Cloudflare]
    CF -->|tunnel| cloudflared
    Tailnet[Tailnet devices] -->|WireGuard| TSProxy[Tailscale operator proxy]
    OpenTofu -.->|provisions| CF & Tailnet & Server

    subgraph Server["Hetzner CX33 - Talos Linux"]
        cloudflared --> Traefik --> Apps
        TSProxy --> Headlamp
        Apps --> CNPG[(PostgreSQL)]
        Flux -->|reconciles| Apps & Headlamp
    end

    CNPG -.->|WAL archive| S3[(Hetzner S3)]
    Apps -.->|daily backup| S3
    Flux -.->|watches| Git[GitHub repo]
```

## Stack

| Tool | Role |
|---|---|
| [Talos Linux](https://talos.dev) | Immutable Kubernetes OS |
| [Flux CD](https://fluxcd.io) | GitOps reconciliation |
| [OpenTofu](https://opentofu.org) | Infrastructure provisioning |
| [Traefik](https://traefik.io) | Ingress + reverse proxy (public apps) |
| [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | Public ingress path, no open ports on the node |
| [Tailscale](https://tailscale.com) | Node management transport + admin-only ingress for Headlamp |
| [Headlamp](https://headlamp.dev) | Flux-aware admin dashboard (Tailnet-only) |
| [CNPG](https://cloudnative-pg.io) | PostgreSQL operator |
| [hcloud-csi](https://github.com/hetznercloud/csi-driver) | Hetzner Volumes CSI for app-data PVCs |
| [SOPS](https://github.com/getsops/sops) | Secret encryption (age + YubiKey) |

## Hardware

Single Hetzner CX33 (4 vCPU, 8 GB, 80 GB NVMe) for ~EUR 7/month + S3 as needed by apps.
No HA: All persistent data lives in S3. Full rebuild from git takes ~20 minutes.

## Development

[mise](https://mise.jdx.dev/) manages tool versions and all project
commands. Run `mise tasks` to see available commands.
