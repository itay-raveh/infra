# `raveh.dev` infrastructure

[![CI](https://github.com/itay-raveh/infra/actions/workflows/ci.yaml/badge.svg)](https://github.com/itay-raveh/infra/actions/workflows/ci.yaml)
[![License](https://img.shields.io/github/license/itay-raveh/infra)](https://github.com/itay-raveh/infra/blob/main/LICENSE)

Built to be as stateless and immutable as possible.
Everything is IaC, data is backed up in S3, so all other infrastructure is essentially ephemeral (namely the VPS).

## Architecture

```mermaid
flowchart
    Cloudflare@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/cloudflare.svg?raw=true, label: Cloudflare, h: 30, constraint: on}
    Cloudflared@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/cloudflared.svg?raw=true, label: Cloudflared, h: 50, constraint: on}
    Tailscale@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/tailscale-light.svg?raw=true, label: Tailscale, h: 50, constraint: on}
    TailscaleOperator@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/tailscale-light.svg?raw=true, label: Tailscale Operator, h: 50, constraint: on}
    Traefik@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/traefik.svg?raw=true, label: Traefik, h: 40, constraint: on}
    GitHubInfra@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/github-light.svg?raw=true, label: GitHub (infra), h: 50, constraint: on}
    GitHubApp@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/github-light.svg?raw=true, label: GitHub (app), h: 50, constraint: on}
    FluxCD@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/flux-cd.svg?raw=true, label: FluxCD, h: 50, constraint: on}
    CNPG@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/cloud-native-pg-light.svg?raw=true, label: CloudNativePG, h: 50, constraint: on}
    Headlamp@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/svg/headlamp-dark.svg?raw=true, label: Headlamp, h: 50, constraint: on}
    Restic@{img: https://github.com/homarr-labs/dashboard-icons/blob/main/png/restic.png?raw=true, label: Restic, h: 50, constraint: on}

    GitHubApp <-.-|reconciles| FluxCD
    GitHubInfra <-.-|watches| FluxCD

    Internet@{shape: cloud} -.- Cloudflare
    Cloudflare -.- Cloudflared

    MyDevices((My Devices)) -.- Tailscale
    Tailscale -.- TailscaleOperator

    subgraph Server["K3S on Talos (Hetzner)"]
        FluxCD -->|deploys| App

        subgraph Public["Public (Traefik)"]
            Cloudflared --- Traefik
            Traefik --- App
        end

        subgraph Private["Private (Tailnet)"]
            TailscaleOperator --- Headlamp
        end

        App --- CNPG
        CNPG -->|backup| Barman

        App --- PVC[(PVC)]
        PVC -->|backup| Restic
        
    end

    Barman -.-> S3[("S3 (Hetnzer)")]
    Restic -.-> S3
```

## Stack

|   |   |
|---|---|
| [Talos Linux](https://talos.dev) | Immutable Kubernetes OS |
| [Flux CD](https://fluxcd.io) | GitOps reconciliation |
| [OpenTofu](https://opentofu.org) | Infrastructure provisioning |
| [Cloudflare Workers](https://developers.cloudflare.com/workers/static-assets/) | Static hosting for `itay.raveh.dev` and `quizmon.raveh.dev` |
| [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | Public ingress without exposing an origin HTTP port |
| [Traefik](https://traefik.io) | Reverse proxy |
| [Tailscale](https://tailscale.com) | Private ingress |
| [Headlamp](https://headlamp.dev) | Flux-aware admin dashboard (Tailnet-only) |
| [CNPG](https://cloudnative-pg.io) | PostgreSQL |
| [Hetzner Object Storage](https://docs.hetzner.com/storage/object-storage/) | Backups, [Wanderbound](https://github.com/itay-raveh/wanderbound) user uploads (presigned S3 PUTs avoid uploading through the Cloudflare tunnel) |
| [SOPS](https://github.com/getsops/sops) | Secret encryption |
