# `raveh.dev` infrastructure

[![CI](https://github.com/itay-raveh/infra/actions/workflows/ci.yaml/badge.svg)](https://github.com/itay-raveh/infra/actions/workflows/ci.yaml)
[![License](https://img.shields.io/github/license/itay-raveh/infra)](https://github.com/itay-raveh/infra/blob/main/LICENSE)

OpenTofu and Flux manage `shire`, a single-node Talos Kubernetes cluster on
Hetzner, and the Cloudflare resources for `raveh.dev`. The server can be rebuilt
from the repository and encrypted state; database and file backups live in S3.

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

| Tool | Role |
|---|---|
| [Talos Linux](https://talos.dev) | Immutable Kubernetes OS |
| [Flux CD](https://fluxcd.io) | GitOps reconciliation |
| [OpenTofu](https://opentofu.org) | Infrastructure provisioning |
| [Cloudflare Workers](https://developers.cloudflare.com/workers/static-assets/) | Static hosting for `itay.raveh.dev` and `quizmon.raveh.dev` |
| [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | Public ingress without exposing an origin HTTP port |
| [Traefik](https://traefik.io) | Reverse proxy |
| [WireGuard](https://www.wireguard.com/) | Private Kubernetes and Talos API access |
| [Tailscale](https://tailscale.com) | Private ingress for Headlamp |
| [Headlamp](https://headlamp.dev) | Flux-aware admin dashboard (Tailnet-only) |
| [CNPG](https://cloudnative-pg.io) | PostgreSQL operator |
| [Hetzner Object Storage](https://docs.hetzner.com/storage/object-storage/) | Backups, [Wanderbound](https://github.com/itay-raveh/wanderbound) user uploads (presigned S3 PUTs avoid uploading through the Cloudflare tunnel) |
| [SOPS](https://github.com/getsops/sops) | Secret encryption with age and YubiKeys |

## Hardware and storage

The cluster uses one Hetzner CX33 in `hel1`, configured in
[tofu/locals.tf](tofu/locals.tf). There is no high availability.

PostgreSQL uses the default local-path storage class. Wanderbound files use
an `hcloud-volumes` PVC provisioned by
[hcloud-csi](clusters/shire/infrastructure/controllers/hcloud-csi.yaml).
[Barman](clusters/shire/apps/wanderbound/objectstore.yaml) backs up PostgreSQL;
[restic](clusters/shire/apps/wanderbound/data-backup.yaml) backs up the file volume.
Rebuilding the server requires a separate [data restore](docs/disaster-recovery.md).

## Development

[mise](https://mise.jdx.dev/) pins tools in `mise.toml` and exposes the operator
commands. Run commands from the repository root with mise active:

```bash
mise install
mise tasks
mise run check
```

`mise run test` runs shell tests. `check` also validates OpenTofu, rendered
Flux/Helm resources, docs and secret handling without cloud credentials.
See [checks and recovery tests](docs/deploying.md#checks).

- `tofu/`: cloud resources and machine configuration, applied with OpenTofu.
- `clusters/shire/`: Kubernetes manifests, reconciled by Flux from `main`.
- `.sops.yaml`: encryption recipients for committed secrets.

## Documentation

- [Setup](docs/setup.md): workstation access and cluster rebuilds.
- [Deploying](docs/deploying.md): infrastructure, manifests, and application releases.
- [Secrets](docs/secrets.md): credential inventory and key rotation.
- [Cloudflare](docs/cloudflare.md): IaC ownership, dashboard settings, and verification.
- [Troubleshooting](docs/troubleshooting.md): diagnostics by symptom.
- [Recovery](docs/disaster-recovery.md): database, file, and cluster restores.
