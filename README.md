# shire - personal infrastructure

[![validate](https://github.com/itay-raveh/infra/actions/workflows/validate.yaml/badge.svg)](https://github.com/itay-raveh/infra/actions/workflows/validate.yaml)
[![License](https://img.shields.io/github/license/itay-raveh/infra)](https://github.com/itay-raveh/infra/blob/main/LICENSE)

GitOps-managed personal infrastructure for `raveh.dev`. Everything sensitive is SOPS-encrypted to YubiKey recipients; the repo is safe to make public at any commit.

## Architecture

```mermaid
graph LR
    Internet -->|HTTPS| CF[Cloudflare Tunnel]
    CF --> Traefik
    Traefik --> Apps

    subgraph Hetzner CX33
        subgraph Talos Linux
            Flux -->|reconciles| Apps
            Traefik
            Apps
            CNPG[(PostgreSQL)]
        end
    end

    Flux -->|watches| Git[GitHub repo]
    OpenTofu -->|provisions| Hetzner CX33
```

## Stack

| Tool | Version | Role |
|---|---|---|
| [Talos Linux](https://talos.dev) | v1.12.6 | Immutable Kubernetes OS |
| [Kubernetes](https://kubernetes.io) | v1.35.2 | Container orchestration |
| [Flux CD](https://fluxcd.io) | v2.8.5 | GitOps reconciliation |
| [OpenTofu](https://opentofu.org) | v1.11.6 | Infrastructure provisioning |
| [Traefik](https://traefik.io) | - | Ingress + reverse proxy |
| [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | - | Zero-trust ingress (no open ports) |
| [CNPG](https://cloudnative-pg.io) | - | PostgreSQL operator |
| [SOPS](https://github.com/getsops/sops) | v3.12.2 | Secret encryption (age + YubiKey) |

## Hardware

| Server | Location | CPU | RAM | Disk | Cost |
|---|---|---|---|---|---|
| Hetzner CX33 | Helsinki (hel1) | 4 vCPU (AMD) | 8 GB | 80 GB NVMe | EUR 6.49/month |

Single node. No HA - the node is cattle. All persistent data lives in S3 backups (CNPG PITR for Postgres, etcd snapshots, app-data tarballs). Full rebuild from git takes ~20 minutes.

## Repo layout

Three top-level planes, each with one owner:

- `tofu/` - OpenTofu: Hetzner server, Cloudflare tunnel and DNS
- `talos/` - SOPS-encrypted Tailscale auth key
- `clusters/shire/` - Flux manifests: in-cluster state (HelmReleases, SOPS-encrypted secrets)

## Development

[mise](https://mise.jdx.dev/) manages tool versions and all project
commands. Run `mise tasks` to see available commands.

## Docs

| Guide | What it covers |
|---|---|
| [setup.md](docs/setup.md) | YubiKey bootstrap ceremony, laptop prerequisites, full cluster rebuild (~20 min) |
| [deploying.md](docs/deploying.md) | Day-to-day workflows: cluster state changes, infra changes, Talos/K8s upgrades |
| [disaster-recovery.md](docs/disaster-recovery.md) | Single points of failure, S3 restore paths, YubiKey loss |
| [secrets.md](docs/secrets.md) | Threat model, SOPS encryption, key rotation |
