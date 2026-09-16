# `raveh.dev` infrastructure

[![CI](https://github.com/itay-raveh/infra/actions/workflows/ci.yaml/badge.svg)](https://github.com/itay-raveh/infra/actions/workflows/ci.yaml)
[![License](https://img.shields.io/github/license/itay-raveh/infra)](https://github.com/itay-raveh/infra/blob/main/LICENSE)

OpenTofu and Flux configuration for Cloudflare and
[`shire`](tofu/locals.tf), a single-node Talos Kubernetes cluster on Hetzner.

[Setup](docs/setup.md) · [Deploying](docs/deploying.md) ·
[Secrets](docs/secrets.md) · [Cloudflare](docs/cloudflare.md) ·
[Troubleshooting](docs/troubleshooting.md) · [Recovery](docs/disaster-recovery.md)

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

    GitHubApp <-.-|watches releases| FluxCD
    GitHubInfra <-.-|watches| FluxCD

    Internet@{shape: cloud} -.- Cloudflare
    Cloudflare -.- Cloudflared

    MyDevices((My Devices)) -.- Tailscale
    Tailscale -.- TailscaleOperator

    subgraph Server["Kubernetes on Talos (Hetzner)"]
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

    Barman -.-> S3[("S3 (Hetzner)")]
    Restic -.-> S3
```

## Stack

| Component | Tools |
|---|---|
| Cluster | [Talos Linux](https://talos.dev), [OpenTofu](https://opentofu.org), [Flux CD](https://fluxcd.io) |
| Public sites | [Cloudflare Workers](https://developers.cloudflare.com/workers/static-assets/), [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/), [Traefik](https://traefik.io) |
| Management | [WireGuard](https://www.wireguard.com/) for cluster APIs; [Tailscale](https://tailscale.com) for [Headlamp](https://headlamp.dev) |
| Data | [CNPG](https://cloudnative-pg.io), [Hetzner Object Storage](https://docs.hetzner.com/storage/object-storage/) for backups and direct [Wanderbound](https://github.com/itay-raveh/wanderbound) uploads |
| Secrets | [SOPS](https://github.com/getsops/sops) with age and YubiKeys |
