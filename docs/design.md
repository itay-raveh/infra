# frodo: Talos + Flux — proposed design

**Status:** DRAFT. The current repo describes a Komodo-based setup. This document describes the proposed future state: a complete rewrite onto Talos Linux + Flux CD. It is written as if the repo were empty. Nothing in here is implemented yet.

**Owner:** Itay Raveh. Iteration happens on this file directly.

---

## 0. Locked decisions

Quick reference for choices made during design iteration. Rationale is inlined in the relevant sections; this table exists so cross-references like "§0.5" resolve to a one-line summary.

| # | Topic | Value |
|---|---|---|
| 0.1 | YubiKey count | Two (primary + backup) |
| 0.2 | YubiKey model | YubiKey 5 series |
| 0.3 | Migration from Komodo | Big-bang: `tofu destroy` current, `tofu apply` new from scratch |
| 0.5 | Cluster API access | **Tailscale SaaS** via `siderolabs/tailscale` extension; coordinator URL is a config knob, so Headscale on a dedicated VM is a future swap, not a redesign |
| 0.6 | Observability scope | **VM k8s-stack + VictoriaLogs + Alloy** (~550 MB) |
| 0.7 | Alert destination | **ntfy.sh public** with unguessable topic |
| 0.8 | Tofu state passphrase | SOPS-encrypted file in repo, YubiKey unlocks at apply time |
| 0.9 | Backup bucket isolation | **Same Hetzner project, dedicated bucket, scoped S3 credential** denying `DeleteObject` |
| 0.10 | Admin email | **`ops@raveh.dev`** — separates human-operator identity from personal identity |

---

## 1. Requirements (pinning the spec before picking tools)

- **GitOps-first.** Source of truth is this repo. Panel DBs are caches.
- **Reproducible.** `tofu apply` + `flux bootstrap` from a clean laptop recreates everything.
- **Versioned.** Every component (Talos, k8s, Flux, every Helm chart, every container image) is pinned. Renovate opens PRs for bumps.
- **Assume-public threat model.** The repo's actual GitHub visibility is a free variable — flip it private or public whenever you want — but the hygiene bar is set as if it were public at every commit. Every secret is SOPS-encrypted to YubiKey recipients before it can be committed. No out-of-band `.env` master key shared between machines. Hardware-backed trust root (YubiKey). Commit messages, issue titles, and file names avoid anything that would be a leak if the repo flipped public tomorrow.
- **Leak scanning is mandatory, not optional.** Pre-commit hook (gitleaks) blocks plaintext secrets locally. CI runs the same scan on every PR as a second layer. A plaintext secret must never reach `origin`, regardless of repo visibility.
- **Single node, personal scale.** Cheap, small blast radius, no HA theatre.
- **Public-facing apps on `*.raveh.dev` behind Cloudflare Tunnel.** No open HTTP ports on the server.
- **Admin plane dark to the public internet.** 6443 (kube-apiserver) and 50000 (talosctl) are never exposed publicly. Access is via Tailscale mesh only (§0.5).
- **Disaster recovery from git + a YubiKey.** If frodo is nuked: `tofu apply`, wait, `flux bootstrap`, done. At v1 there is no stateful data worth restoring — every component rebuilds from git. When phase 2 lands (§16), Postgres gains its own Barman/S3 recovery path.
- **v1 is deliberately minimal.** Everything that can be deferred until the first real app lands, is deferred. See §16 for what comes in phase 2.

Non-goals: multi-tenant, HA, strict production SLOs, multi-cluster.

---

## 2. Stack selection

**v1 (this document):** the full platform — Talos, Flux, cloudflared, **Traefik**, SOPS+age+YubiKey, Tailscale admin access. No user-facing apps. Traefik is part of the platform (every future HTTP app plugs into it), so it ships at v1; with zero IngressRoutes defined it returns a native 404 for every host, which is the exact end-user behavior we want while the cluster is empty. The point of v1 is to prove the rebuild path end-to-end (tofu → Talos → Flux → DNS → edge → tunnel → Traefik) with the full edge path in place.

**Phase 2 (§16):** CloudNativePG + Postgres, observability (VM stack + VictoriaLogs + Alloy + ntfy), Velero, Renovate, hcloud-ccm, and the fullstack app itself. A status page (if we still want one) lands here too — likely an **external** uptime checker (Healthchecks.io, Better Stack, or a Cloudflare Worker on a cron) rather than in-cluster, because an in-cluster status page shares fate with the thing it's monitoring.

### 2.1 v1 components

| Layer | Choice | Why |
|---|---|---|
| IaC | **OpenTofu** + client-side state encryption (AES-GCM / PBKDF2) | State lives in Hetzner Object Storage; encryption independent of backend ([docs](https://opentofu.org/docs/language/state/encryption/)) |
| Host | **Hetzner Cloud CAX21** (ARM, 4 vCPU, 8 GB) | Confirmed. €6.29/mo. Headroom for phase-2 additions without resizing |
| OS | **Talos Linux**, pinned | Immutable, API-only, k8s-native, no SSH, declarative |
| Talos config | **talhelper** ([budimanjojo/talhelper](https://github.com/budimanjojo/talhelper)) | Generates machineconfig from cluster-level intent + SOPS secrets |
| Provisioning module | **hcloud-talos/terraform-hcloud-talos** ([registry](https://registry.terraform.io/modules/hcloud-talos/talos/hcloud/latest)) | Community module: server + volume + network + Talos apply + bootstrap |
| k8s distro | Upstream Kubernetes bundled with Talos | Talos runs vanilla k8s, not k3s |
| CNI | **Flannel** (Talos default) | Cilium eats ~300 MB more RAM; single-node without NetworkPolicy, Flannel is enough |
| Storage | **local-path-provisioner** on `/var/mnt/data` | Dynamic PVCs on the Hetzner Volume ([Rancher LPP](https://github.com/rancher/local-path-provisioner)) |
| Edge / DNS | **Cloudflare Tunnel** + Access | cloudflared runs as a k8s Deployment; tunnel config is a single wildcard rule `* → traefik.svc:80` that stays unchanged across phases |
| HTTP routing | **Traefik** (HelmRelease) | Single reverse proxy behind cloudflared. At v1 no IngressRoutes → Traefik's default 404 for every host. Phase 2 apps add `IngressRoute`/`Ingress` resources and light up hostnames |
| TLS at origin | **None needed** | Traefik ↔ Service is in-cluster; edge terminates HTTPS |
| GitOps | **Flux v2** (`flux bootstrap github`) | No panel DB, reconciliation is the only state ([Flux bootstrap docs](https://fluxcd.io/flux/installation/bootstrap/github/)) |
| Secrets in git | **SOPS + age + age-plugin-yubikey** | Hardware-backed encryption, touch-to-decrypt ([Flux SOPS guide](https://fluxcd.io/flux/guides/mozilla-sops/)) |
| Cluster API access | **Tailscale** as Talos system extension (`siderolabs/tailscale`) | Closes 6443 + 50000 to the public internet; phone access ready when needed |
| Leak scanning | **[gitleaks](https://github.com/gitleaks/gitleaks)** as pre-commit hook + GitHub Actions job | Assume-public threat model (§1) makes this a hard requirement; blocked locally AND on PR |
| CI | GitHub Actions: `gitleaks`, `sops-sanity`, `flux-build`, `tofu-validate` | Catches plaintext leaks, SOPS regressions, broken Kustomizations, and tofu syntax before merge |

### 2.2 Deferred to phase 2

| Component | §0 / detail | Rationale for deferral |
|---|---|---|
| Hetzner CCM | §0 default | No LoadBalancer services; node labels are nice-to-have. Add only if a workload actually needs it. |
| `victoria-metrics-k8s-stack` + VictoriaLogs + Alloy + ntfy | §0.6 / §0.7 | Nothing to observe at v1. Add with the fullstack app so RED metrics, Postgres dashboard, and alerts land together. |
| Velero FSB | — | No critical state at v1. Postgres backups will go through CNPG/Barman directly (§16), not Velero. |
| Renovate | — | Infra deps are fresh on day 1. Add in month 2+ once churn starts. |
| CloudNativePG operator + Postgres `Cluster` | new in phase 2 | Lands with the fullstack app that needs the DB. |
| kubeconform in CI | — | `flux-build` catches most schema issues. Add when it bites. |

---

## 3. Hardware sizing

**Server: Hetzner Cloud CAX21** — Ampere ARM64, 4 vCPU, 8 GB RAM, 80 GB NVMe, 20 TB egress/month, €6.29/mo in `hel1`. ([Hetzner Cloud pricing](https://www.hetzner.com/cloud))

**Persistent volume: Hetzner Cloud Volume** — 40 GB ext4 attached as block device, mounted at `/var/mnt/data`, €1.60/mo (0.04 €/GB/month). ([Hetzner Volumes](https://docs.hetzner.com/cloud/volumes/overview/))

**Total infra cost floor:** ~€8/mo before Object Storage (backups + tofu state). Object Storage is €5.99/mo for the first 1 TB, so budget ~€14/mo all-in.

### 3.1 RAM budget — v1

Numbers below are conservative steady-state RSS from upstream chart defaults + community reports (home-ops repos, Talos docs). v1 deliberately carries only the platform — no apps at all; phase-2 additions are budgeted separately in §16.

| Component | RSS | Source / note |
|---|---|---|
| Talos + kubelet + containerd | ~400 MB | Talos system requirements page, single-node control-plane profile |
| kube-apiserver + etcd + controller-manager + scheduler | ~700 MB | Vanilla k8s 1.35 footprint, small cluster |
| Flannel | ~80 MB | Default DaemonSet |
| Flux core (source, kustomize, helm, notification) | ~200 MB | No image-automation controllers |
| cloudflared | ~80 MB | Single replica Deployment; tunnel routes `* → traefik.svc:80` |
| Traefik | ~80 MB | Single replica; returns default 404 until phase 2 adds IngressRoutes |
| local-path-provisioner | ~30 MB | Rancher chart; no PVCs bound at v1 |
| Tailscale (Talos system extension, host-level) | ~30 MB | `tailscaled` daemon, not a pod |
| **Platform steady-state** | **~1.6 GB** | |
| **Headroom for phase 2 + app** | **~6.4 GB** | Room for CNPG (~350) + observability (~750) + fullstack app (Vue ~50, FastAPI ~150) ≈ ~1.3 GB added, ~5 GB still free |

### 3.2 Disk budget

| Path | Size | Used by |
|---|---|---|
| `/` (root, Talos install disk, 80 GB NVMe) | ~80 GB | Talos OS, container image cache, ephemeral volumes |
| `/var/mnt/data` (Hetzner Volume, 40 GB, expandable) | ~40 GB | local-path PVCs, etcd data, VictoriaMetrics TSDB, VictoriaLogs, Grafana, app PVCs |

Split rationale: the root disk is ephemeral from a recovery standpoint (it's recreated on `tofu apply`), while `/var/mnt/data` persists across server rebuilds (`prevent_destroy = true` on the Volume resource). Everything that must survive a rebuild goes under `/var/mnt/data`.

Expected `/var/mnt/data` breakdown at v1 steady state:
- etcd data: ~500 MB
- Headroom: ~39.5 GB

Phase 2 (§16) will reserve roughly: VictoriaMetrics TSDB (14-day retention) ~2 GB, VictoriaLogs (7-day) ~1 GB, Grafana SQLite ~100 MB, Postgres cluster ~2 GB, Velero staging (if used) ~1 GB. Still leaves ~30 GB headroom on the 40 GB volume.

Hetzner Volumes can grow online up to 10 TB — no downtime when we need more. Don't oversize at start.

### 3.3 CPU and network

Neither is a constraint at this scale. 4 Ampere vCPU idles under 10%, with brief Helm-upgrade spikes to ~60% of one core; CAX21's 20 TB/month outbound quota sees low-MB personal traffic (phase 2 Grafana + Postgres uploads stay well under 1 GB/month). Inbound is uncapped.

### 3.4 If the sizing turns out wrong

Upgrading CAX21 → CAX31 (8 vCPU, 16 GB, €11.66/mo) is a one-line tofu change + reboot. The Hetzner Volume survives. Don't over-provision at the start — resize reactively.

---

## 4. Repo layout

```
infra/
├── README.md                   # overview, architecture diagram, quickstart, link to docs/setup.md
├── LICENSE                     # MIT, Itay Raveh
├── .gitignore                  # .env, *.tfstate, *.tfplan, .terraform/, kubeconfig, talosconfig, *.decrypted.*
├── .env.example                # TF_VAR_* (incl. TF_VAR_encryption_passphrase), AWS_*, SOPS_AGE_KEY_FILE
├── .editorconfig
│
├── docs/
│   ├── design.md               # this file
│   ├── setup.md                # first-time bootstrap, laptop-side prereqs
│   ├── deploying.md            # how to add a new app
│   ├── disaster-recovery.md    # full rebuild from zero
│   └── secrets.md              # age key handling, YubiKey rotation, PIN/touch policy
│
├── .github/workflows/
│   └── validate.yaml           # gitleaks + sops-sanity + flux build + tofu validate
│
├── .pre-commit-config.yaml     # gitleaks, sops-verify, tofu fmt, yamllint
│                               # REQUIRED to install: `pre-commit install` in every clone
│
├── .mise.toml                  # opentofu, talosctl, flux, sops, age, age-plugin-yubikey,
│                               # kubectl, gh, gitleaks, pre-commit, jq, yq, tailscale, yamllint
│
├── .sops.yaml                  # age recipients (2 YubiKeys + 1 cluster software key) + path regexes
│
├── bootstrap/
│   ├── README.md               # explains the chicken-and-egg: what this dir is for
│   └── cluster-age.key.sops    # cluster software age key, encrypted to both YubiKeys.
│                               # This is the ONLY reason the repo can be used for disaster recovery.
│
├── tofu/
│   ├── backend.tf              # S3 backend on Hetzner Object Storage, client-side encryption
│   ├── versions.tf             # provider pins (hcloud, cloudflare, talos, imager, random, sops)
│   ├── variables.tf            # hcloud_token, tailscale_auth_key, cloudflare_*, ssh pub key
│   ├── locals.tf               # cluster name, region, version pins (tofu-side source of truth)
│   ├── main.tf                 # hcloud-talos module, imager_image, hcloud_volume, volume_attachment, patch locals
│   ├── talos.tf                # talos_image_factory_schematic + raw.xz URL local
│   ├── cloudflare.tf           # tunnel, tunnel config (* → traefik.svc:80), DNS
│   └── outputs.tf              # tunnel_token, server IPv4, kubeconfig path
│
├── talos/
│   └── tailscale-authkey.sops.txt   # SOPS-encrypted Tailscale pre-auth key (single string)
│
└── clusters/frodo/
    ├── flux-system/            # written by `flux bootstrap`, don't hand-edit
    └── infrastructure/
        ├── sources/            # HelmRepository resources (one per chart source)
        │   ├── cloudflared.yaml
        │   ├── traefik.yaml
        │   └── local-path-provisioner.yaml
        ├── controllers/
        │   ├── local-path-provisioner/
        │   │   └── release.yaml
        │   ├── cloudflared/
        │   │   ├── release.yaml
        │   │   └── tunnel-token.sops.yaml  # written post-`tofu apply`
        │   └── traefik/
        │       └── release.yaml
        └── kustomization.yaml
```

v1 ships with **no `apps/` subtree at all** — the platform has nothing to host yet. Phase 2 (§16) adds `apps/` alongside `infrastructure/controllers/{hcloud-ccm,victoria-metrics,victoria-logs,grafana,alloy,velero,cnpg-operator,renovate}/`, a `renovate.json` at repo root, and the corresponding `sources/` entries. All additive — no restructure.

**Conventions:**

- **Three top-level planes:** `tofu/` = imperative-at-apply-time infrastructure (what tofu owns), `talos/` = declarative machineconfig input (what talhelper renders), `clusters/frodo/` = declarative in-cluster state (what Flux reconciles). Each plane has exactly one owner — no overlap.
- **`infrastructure/` vs `apps/`:** infra is everything that must be up before a user-facing app can work (ingress, CCM, storage, observability, backups). Apps depend on infra via Flux `dependsOn`. A new app is a new directory under `apps/` plus one line in `apps/kustomization.yaml` — nothing in `infrastructure/` needs to change.
- **Two Flux `Kustomization` resources at cluster root:** `infrastructure` (no deps), `apps` (depends on `infrastructure`). Standard Flux layout ([repository structure](https://fluxcd.io/flux/guides/repository-structure/)).
- **Naming:** encrypted files ALWAYS end in `.sops.yaml` (or `.sops.json`). The `.sops.yaml` config file is the only exception and lives at repo root. Pre-commit enforces that no `.yaml` file outside this pattern contains fields matching SOPS payload signatures (prevents "forgot to encrypt" mistakes).
- **`bootstrap/` is special.** Everything else in the repo is reconciled by Flux; `bootstrap/` is the set of artifacts needed *before* Flux exists on a fresh cluster. Treat it as read-only post-bootstrap.
- **No `env/` or per-environment dirs.** Single cluster, single environment. If we ever add staging, it'll be `clusters/staging/` as a sibling. No "dev vs prod" branching.

---

## 5. Provisioning layer — `tofu/`

### 5.1 State encryption

`backend.tf` declares an S3 backend on Hetzner Object Storage (`raveh-infra-tfstate` bucket, `hel1` endpoint, path-style, `skip_*` flags for non-AWS S3) plus an `encryption` block: PBKDF2 key provider whose `passphrase` is sourced from `var.encryption_passphrase` (declared `sensitive = true` in `variables.tf`), AES-GCM method, applied to both `state` and `plan`. OpenTofu's early-evaluation in encryption blocks supports `var.*` references but not a generic `env()` reader, so the passphrase travels in via the standard `TF_VAR_*` mechanism. ([OpenTofu state encryption](https://opentofu.org/docs/language/state/encryption/))

**Passphrase flow (§0.8):** `tofu/encryption-passphrase.sops.txt` is committed to the repo, encrypted to both YubiKey recipients. A `mise run tofu-apply` task unwraps it (`sops --decrypt`), exports it as `TF_VAR_encryption_passphrase`, and runs `tofu -chdir=tofu apply "$@"`. OpenTofu picks it up as `var.encryption_passphrase` at plan/apply time. YubiKey touch once per invocation; passphrase never lands on disk in plaintext. AWS creds for the S3 backend come from the same flow (Hetzner Object Storage access key + secret, SOPS-wrapped).

### 5.2 Talos image (Image Factory)

`talos.tf`:

```hcl
data "talos_image_factory_extensions_versions" "this" {
  talos_version = local.talos_version
  filters       = { names = ["hcloud", "qemu-guest-agent", "tailscale"] }
}

resource "talos_image_factory_schematic" "frodo" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
    }
  })
}

locals {
  # Raw disk image URL consumed by the hcloud-talos/imager provider (§5.3).
  talos_image_raw_url = "https://factory.talos.dev/image/${talos_image_factory_schematic.frodo.id}/${local.talos_version}/hcloud-arm64.raw.xz"
}
```

**Extensions pulled into the image:**

| Extension | Purpose |
|---|---|
| `siderolabs/hcloud` | Hetzner metadata integration, sets hostname and networking from Hetzner's metadata service |
| `siderolabs/qemu-guest-agent` | Hetzner uses QEMU; lets Hetzner host issue graceful reboots, freeze filesystem on snapshot |
| `siderolabs/tailscale` | Runs `tailscaled` as a host-level `ExtensionService`, managed by Talos. Auth key is injected via the `hcloud-talos/talos/hcloud` module's `tailscale` input (§5.3), which we feed from a SOPS-encrypted file at apply time. |

Schematic ID → `hcloud-arm64.raw.xz` URL → `imager_image` resource uploads it to Hetzner as a snapshot → `hcloud-talos/talos/hcloud` module consumes the snapshot ID. The Image Factory's container-image "installer" URL is not used here because v3.2.3 of the module only accepts Hetzner snapshot/ISO IDs, not factory URLs.

### 5.3 Server + volume (via module + imager)

**Image snapshot step.** The `hcloud-talos/talos/hcloud` module v3.2.3 does not consume a factory URL directly — it expects a pre-built Hetzner snapshot. The companion `hcloud-talos/imager` Terraform provider bridges that gap: given a `.raw.xz` URL, it uploads the disk image to Hetzner and returns a snapshot ID.

```hcl
resource "imager_image" "frodo" {
  architecture = "arm"
  image_url    = local.talos_image_raw_url
  location     = local.hcloud_location
  description  = "Talos ${local.talos_version} (frodo schematic)"
  labels       = { os = "talos", schematic = talos_image_factory_schematic.frodo.id }
}
```

**Module call.** Note the v3.2.3 API: flat `control_plane_nodes` list (no nodepools, no per-node `image` field), `location_name` at module level, built-in `tailscale` wiring, and both API firewalls defaulting closed (we just leave them unset).

```hcl
module "talos" {
  source  = "hcloud-talos/talos/hcloud"
  version = "= 3.2.3"

  cluster_name       = local.cluster_name
  cluster_prefix     = true                              # so server name becomes "frodo-control-plane-1"
  location_name      = local.hcloud_location
  hcloud_token       = var.hcloud_token
  talos_version      = local.talos_version
  kubernetes_version = local.kubernetes_version

  # Custom snapshot from imager_image carries our Image Factory extensions.
  talos_image_id_arm = imager_image.frodo.id
  disable_x86        = true

  control_plane_nodes = [
    { id = 1, type = local.hcloud_server_type },
  ]
  worker_nodes                 = []
  control_plane_allow_schedule = true

  # Cluster API (6443) and Talos API (50000) are NOT exposed to the public
  # internet at all. Access happens over Tailscale (§0.5). The module's default
  # is "block all", which is what we want, so firewall_kube_api_source and
  # firewall_talos_api_source are left at null.
  firewall_use_current_ip = false

  # Tailscale as a Talos ExtensionService, managed by the module. The auth key
  # is a sensitive tofu variable that the mise tofu-apply task fills in from
  # talos/tailscale-authkey.sops.txt at apply time.
  tailscale = {
    enabled  = true
    auth_key = var.tailscale_auth_key
  }

  # Patches the module can't express directly — e.g. mounting the Hetzner
  # Volume into the Talos host namespace so workloads can bind it in.
  talos_control_plane_extra_config_patches = [local.patch_data_volume_mount]
}

locals {
  patch_data_volume_mount = yamlencode({
    machine = {
      kubelet = {
        extraMounts = [{
          destination = "/var/mnt/data"
          type        = "bind"
          source      = "/var/mnt/data"
          options     = ["bind", "rshared", "rw"]
        }]
      }
    }
  })
}
```

**Volume + attachment.** The module doesn't know about our data volume, so we create and attach it ourselves after the server is up. Server IDs are not exported by the module, so we look up the first control-plane server by its deterministic name (`frodo-control-plane-1`, because `cluster_prefix = true`).

```hcl
resource "hcloud_volume" "data" {
  name     = "frodo-data"
  size     = 40
  location = local.hcloud_location
  format   = "ext4"

  lifecycle { prevent_destroy = true }
}

data "hcloud_server" "frodo_cp1" {
  name       = "${local.cluster_name}-control-plane-1"
  depends_on = [module.talos]
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = data.hcloud_server.frodo_cp1.id
  automount = false
}
```

### 5.4 Talos machineconfig (patches as tofu locals, no talhelper)

`hcloud-talos/talos/hcloud` v3.2.3 renders the base machineconfig internally (it owns PKI, bootstrap token, CNI, CCM, control-plane API endpoint) and applies it to the node itself via the `talos_machine_configuration_apply` resource in its own `talos.tf`. Everything we'd otherwise express in a `talhelper` rendering step becomes either:

- **A direct module input** — Tailscale, Kubernetes version, extra kubelet args, etc.
- **An extra YAML patch string** passed via `talos_control_plane_extra_config_patches = [yamlencode({...}), ...]` — for things the module doesn't express directly (like our `kubelet.extraMounts` for the Hetzner Volume, above).

This means the repo does **not** contain `talos/talconfig.yaml`, `talos/talsecret.sops.yaml`, or `talos/patches/*.yaml`. The only file under `talos/` is `tailscale-authkey.sops.txt` — a SOPS-encrypted text file containing the Tailscale pre-auth key as a single string. The `mise run tofu-apply` task decrypts it (YubiKey touch), exports it as `TF_VAR_tailscale_auth_key`, and runs tofu — the passphrase and Tailscale key then both travel through process memory, never hitting disk in plaintext.

Talos cluster PKI + bootstrap token + etcd encryption key are generated and stored inside the module's tofu state, protected by the same client-side state encryption as everything else (§5.1). No separate `talsecret.sops.yaml` to manage.

**Cluster endpoint:** the module writes the kubeconfig with `kubeconfig_endpoint_mode = "public_ip"` by default, which bakes the public IPv4 into the local kubeconfig file — fine for `kubectl` from your laptop as long as you're inside a Tailscale-authenticated path. The Kubernetes API firewall is closed to the public internet (§5.3), so `kubectl` only works when you're on the tailnet and reach the server over Tailscale. The kubeconfig's SAN certs include the public IP so TLS validates cleanly.

### 5.5 Cloudflare

`tofu/cloudflare.tf` owns:

- **`cloudflare_zero_trust_tunnel_cloudflared` "frodo"** — the tunnel itself. Its token is a tofu output, consumed in §6.B step 4 (`mise run tofu-secrets-sync`) and committed to `clusters/frodo/infrastructure/controllers/cloudflared/tunnel-token.sops.yaml`.
- **`cloudflare_zero_trust_tunnel_cloudflared_config`** — one wildcard ingress rule: `* → http://traefik.traefik.svc.cluster.local:80`. Host-header routing is Traefik's job. Keeping the tunnel config dumb (one rule) means adding a new app is a pure in-cluster change — no tofu run.
- **DNS:** apex `raveh.dev` CNAME + wildcard `*.raveh.dev` CNAME, both targeting `<tunnel-id>.cfargotunnel.com`, both proxied. One tofu apply covers all current and future subdomains.
- **No Access applications at v1.** Nothing is public-facing yet. Phase 2 (§16) adds `cloudflare_zero_trust_access_application` entries for any admin UIs (Grafana, etc.) at the same time those apps land.
- **Important gotcha:** Cloudflare's default bot fight mode returns `403` to internal HTTP probes regardless of their legitimacy. Set `cloudflare_bot_management { fight_mode = false }` on the zone before Traefik starts routing real traffic in phase 2.

**Tofu does not manage the Cloudflare Tunnel's client-side credentials.** The tunnel token is generated by Cloudflare when the tunnel resource is created, flows through tofu outputs, then through SOPS into the cluster. Only cloudflared inside the cluster consumes it at runtime.

### 5.6 GitHub

**Tofu does not own GitHub state.** Branch protection on `main` (required status checks from §10, no force-push, no direct-to-main, no admin bypass) is applied once during §6.A setup via a `mise run branch-protect` task that shells out to `gh api repos/:owner/:repo/branches/main/protection`. One setting, one command, no provider to maintain and no `github_token` variable in `.env` for daily operations. The `gh` CLI uses your interactive `gh auth login` session.

Repo visibility is a UI click whenever you want (§1 sets the security posture as if it were public, so on-disk state is safe to publish at any commit). Webhooks are off — Flux pulls on a 1-minute interval; push-based would require exposing a cluster endpoint publicly, which §0.5 rules out. `flux bootstrap github` creates its own deploy key during setup and commits it as a sealed secret under `flux-system/`; Flux owns its own credentials end-to-end to avoid a chicken-and-egg with tofu.

---

## 6. Cluster bootstrap — the manual sequence

Goal: two documented sequences in `docs/setup.md`. The **one-time setup** path runs once in the life of the repo and produces artifacts that then live in git. The **every-rebuild** path is what you run on a fresh laptop + fresh Hetzner account to reach a running cluster; it's what disaster recovery uses (§14). Target: ~20 minutes wall-clock for a full rebuild.

### 6.A One-time setup (runs once in the life of the repo)

These steps produce committed artifacts that make the repo self-bootstrapping thereafter. Do them once, carefully, in order.

1. **Create the external prerequisites.** These live outside any tool we run:
   - A Hetzner Cloud project, with an API token scoped `Read & Write`.
   - A Hetzner Object Storage bucket for tofu state (`raveh-infra-tfstate`) + S3 credential.
   - A Cloudflare account with `raveh.dev` on it, API token scoped to Zone:DNS edit + Zero Trust edit on this zone only.
   - A GitHub account (`itay-raveh`) and a local `gh auth login` session. The `gh` CLI is used twice in §6.A (apply branch protection once) and during each rebuild (§6.B step 5 — `flux bootstrap github` reads `GITHUB_TOKEN` from the environment or from `gh auth token`).
   - A Tailscale account (free tier) with a tailnet, an ACL tag `tag:frodo` defined, and a reusable pre-auth key for that tag (90-day expiry is fine since we're capturing it in SOPS).

   Phase 2 (§16) adds: a second Object Storage bucket + scoped credential for backups, an ntfy.sh topic, and any admin-email allowlists for Cloudflare Access.

2. **Laptop prereqs.** `mise install` reads `.mise.toml` and pulls: `opentofu`, `talosctl`, `flux`, `kubectl`, `gh`, `sops`, `age`, `age-plugin-yubikey`, `gitleaks`, `pre-commit`, `jq`, `yq`, `tailscale`, `yamllint`. `pre-commit install` in the repo activates the hooks.

3. **Initialize both YubiKeys.** Plug in primary: `age-plugin-yubikey --generate --slot 1 --touch-policy cached --pin-policy once`. Record the public key (`age1yubikey1...`). Repeat for the backup YubiKey in a separate slot. **Store one YubiKey offsite** immediately after this step.

4. **Generate the cluster software age key.** `age-keygen -o /tmp/cluster.key`. This is the key Flux's kustomize-controller will use to decrypt `*.sops.yaml` files in-cluster. It exists as plaintext for about 30 seconds.

5. **Write `.sops.yaml`.** Add three recipients: both YubiKey public keys AND the cluster software key's public key. Create the path rules per §7.3.

6. **Encrypt the cluster software key to both YubiKeys only.**
   ```
   sops --encrypt --age <yubikey1,yubikey2> /tmp/cluster.key \
     > bootstrap/cluster-age.key.sops
   shred -u /tmp/cluster.key
   ```
   Note: the cluster key cannot decrypt itself, so the `.sops.yaml` rule for `bootstrap/cluster-age.key.sops` excludes it from the recipient list.

7. **Encrypt the state passphrase.** Generate a strong random passphrase, encrypt it:
   ```
   openssl rand -base64 48 | sops --encrypt --input-type binary /dev/stdin \
     > tofu/encryption-passphrase.sops.txt
   ```
   Touch YubiKey. This satisfies §0.8.

8. **Encrypt the Tailscale auth key.** Generate a reusable pre-auth key for `tag:frodo` in the Tailscale admin console, then:
    ```
    printf '%s' 'tskey-auth-<redacted>' \
      | sops --encrypt --input-type binary /dev/stdin \
      > talos/tailscale-authkey.sops.txt
    ```
    The `mise run tofu-apply` task (§6.B step 3) decrypts this and exports it as `TF_VAR_tailscale_auth_key`, which the `hcloud-talos/talos/hcloud` module consumes via its `tailscale = { enabled, auth_key }` input (§5.3). The key never lands on disk in plaintext after this step.

9. **Talos cluster secrets are handled by the module.** Cluster PKI root, bootstrap token, and etcd encryption key are generated by `hcloud-talos/talos/hcloud` on first apply and live inside tofu state — which is itself AES-GCM encrypted (§5.1). No separate `talsecret.sops.yaml` to manage, no `talhelper gensecret` step.

10. **Write `.env.example`** with the variable names (no values). Commit.

11. **Apply branch protection on `main`.** `mise run branch-protect`. The task calls `gh api repos/itay-raveh/infra/branches/main/protection --method PUT` with the rules from §5.6. One-shot; re-run anytime to reassert.

12. **Commit and push everything.** At this point `bootstrap/`, `.sops.yaml`, `tofu/encryption-passphrase.sops.txt`, `talos/tailscale-authkey.sops.txt`, and `.env.example` are all in git. The repo is now self-bootstrapping.

### 6.B Every-rebuild path (runs on any clean laptop + Hetzner account)

This is the disaster-recovery path and the "I'm setting this up on a new laptop" path. It assumes §6.A artifacts are already in git. Target: ~20 minutes.

1. **Clone the repo, install mise tools, `pre-commit install`, plug in a YubiKey.**

2. **Fill `.env`** from `.env.example`:
   - `TF_VAR_hcloud_token` — from Hetzner
   - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — the tfstate bucket credential
   - `TF_VAR_cloudflare_api_token`, `TF_VAR_cloudflare_zone_id`
   - `TF_VAR_ssh_public_key_path` — for Hetzner rescue mode break-glass

   Plus: run `gh auth login` so `flux bootstrap github` (step 5) can read `GITHUB_TOKEN` via `gh auth token`.

3. **`mise run tofu-apply`.** The task unwraps the state passphrase from `tofu/encryption-passphrase.sops.txt` AND the Tailscale auth key from `talos/tailscale-authkey.sops.txt` (one YubiKey touch per file), exports them as `TF_VAR_encryption_passphrase` and `TF_VAR_tailscale_auth_key`, then runs `tofu apply`, which:
   - Builds the custom Talos schematic at the Image Factory (extensions baked in: hcloud, qemu-guest-agent, tailscale), then uploads the `hcloud-arm64.raw.xz` image into Hetzner as a snapshot via the `imager` provider
   - Creates the CAX21 server from that snapshot
   - Attaches the persistent Hetzner Volume at `/var/mnt/data` via a `kubelet.extraMounts` patch
   - Closes 6443 + 50000 in the Hetzner firewall (§5.3)
   - Lets the `hcloud-talos` module render the Talos machineconfig with the Tailscale input wired in, apply it to the node, and bootstrap etcd
   - At first boot, `tailscaled` starts inside the Talos extension, reads the auth key, joins the tailnet as `frodo`
   - Writes a local kubeconfig pointing at the server's public IP (kubectl only reaches it when you're on the tailnet, since 6443 is firewalled)
   - Outputs: tunnel token, public IP, Tailscale node name

4. **`mise run tofu-secrets-sync`.** Pipes the two tofu outputs that are runtime secrets (not inputs) through SOPS and into the cluster config tree:
   ```
   tofu output -raw tunnel_token | sops --encrypt --input-type binary /dev/stdin \
     > clusters/frodo/infrastructure/controllers/cloudflared/tunnel-token.sops.yaml
   git add clusters/.../tunnel-token.sops.yaml
   git commit -m "chore: tunnel token for fresh tunnel"
   git push
   ```
   On every rebuild Cloudflare generates a fresh tunnel token; the committed ciphertext changes each time. This is the one bespoke step of the rebuild — everything else is idempotent.

5. **`mise run flux-bootstrap`.** Runs:
   ```
   flux bootstrap github \
     --owner=itay-raveh \
     --repository=infra \
     --path=clusters/frodo \
     --personal \
     --branch=main
   ```
   Flux installs itself into the cluster, creates its own GitHub deploy key, commits `clusters/frodo/flux-system/`. `--personal` is the flag that matters here; visibility (public or private) is orthogonal and `flux bootstrap` works either way.

6. **Install the `sops-age` secret** (the one piece of cluster state that can't itself be reconciled from git, because it's what Flux needs *to* reconcile):
   ```
   sops --decrypt bootstrap/cluster-age.key.sops \
     | kubectl create secret generic sops-age \
         -n flux-system \
         --from-file=age.agekey=/dev/stdin
   ```
   YubiKey touch. This is the bootstrap's only chicken-and-egg.

7. **Flux reconciles `infrastructure/`** (cloudflared, traefik, local-path-provisioner). No `apps/` Kustomization at v1. Watch with `flux get kustomizations --watch`. ~3 minutes from zero.

8. **Verify:**
   - `tailscale status` — `frodo` shows as online in your tailnet
   - `kubectl get nodes` (resolves through Magic DNS)
   - `kubectl -n traefik get pods` — Traefik pod is Running
   - `curl -sI https://raveh.dev` — returns `404 Not Found` served by Traefik through the tunnel (proves DNS → edge → tunnel → Traefik end-to-end; no backend yet is expected)

### 6.C What makes rebuild fast

Everything decrypt-then-apply happens locally on the operator's laptop with the YubiKey present. No interactive clicks in cloud UIs (Hetzner, Cloudflare, GitHub) beyond the one-time bucket/project creation in §6.A. No manual secret entry — every secret that tofu doesn't generate is committed as ciphertext. The only cluster state that isn't git is the `sops-age` secret in step 6, and that's unwrapped from `bootstrap/cluster-age.key.sops` which IS in git.

---

## 7. Secrets — the full story

### 7.1 Threat model (what we're defending against, what we're not)

**In scope:**

- **Repository leakage.** The repo is treated as if it were public regardless of its actual GitHub visibility (§1): anyone with a clone can read every encrypted file. Defense: SOPS + age payloads are safe to publish — AES-256-GCM with public-key recipients. ([Flux SOPS guide](https://fluxcd.io/flux/guides/mozilla-sops/)) This means flipping the repo public is a zero-impact event, not a security migration.
- **Accidental plaintext commit.** A plaintext `.env` or leaked token in a commit message. Defense: pre-commit gitleaks (local, blocking) + gitleaks in CI (second layer) + file naming convention that forces the `.sops.yaml` suffix.
- **Laptop compromise.** Attacker on your laptop can't decrypt anything without a physical YubiKey touch (PIV slot, touch-cached mode). Plaintext decrypted secrets live in `$EDITOR` memory for seconds, not on disk.
- **Single YubiKey loss.** Backup YubiKey is the other recipient on every file. Rotate the lost YubiKey out of `.sops.yaml` via `sops updatekeys`.
- **Cluster compromise that reads k8s etcd.** Attacker inside the cluster can read the `sops-age` secret (the cluster software key) and decrypt everything. Defense: Talos immutability + no SSH + 6443/50000 closed to public = compromise requires an in-cluster foothold first.

**Out of scope:**

- **Nation-state adversary.** We're defending against opportunistic attackers, script kiddies, and "someone found my leaked token on GitHub" — not against adversaries who can coerce you into touching a YubiKey.
- **Both YubiKeys lost simultaneously.** That's total cryptographic loss. Mitigation is "keep the backup offsite and don't lose both." No recovery path otherwise.
- **Supply chain attacks on Talos / Flux / Helm charts.** Renovate + pinning + signature verification (where charts support it) reduces risk but doesn't eliminate it.
- **Tofu state bucket compromise.** If the Hetzner Object Storage credential for `raveh-infra-tfstate` leaks, an attacker gets tofu state — which contains secret outputs like the current tunnel token. Defense: state is encrypted client-side with PBKDF2 + AES-GCM, passphrase in SOPS. Ciphertext alone is useless.
- **Compromise of Tailscale Inc.** If Tailscale's coordinator is compromised, admin access to the cluster is compromised. Mitigation: Hetzner rescue console as break-glass (§8.3), Headscale as a future swap (§0.5).

### 7.2 Trust roots

**Hardware roots:** two YubiKey 5s (primary + backup). Private keys live only in PIV slot 1 on the hardware and cannot be extracted. Touch-cached policy means one touch authorizes multiple decryptions within a short window (~15s). PIN-once policy means one PIN entry per boot.

**In-cluster helper:** one software age key, stored as `bootstrap/cluster-age.key.sops` (encrypted to both YubiKeys). Flux's kustomize-controller uses this key to decrypt `*.sops.yaml` files during reconciliation, because a physical YubiKey cannot be present inside a cluster.

**Why three recipients (2 YubiKeys + 1 software), not two:**
- The 2 YubiKeys let the operator encrypt/decrypt files from the laptop with hardware backing and touch confirmation.
- The software key lets Flux decrypt files in-cluster.
- All three can decrypt everything, so losing any single one is recoverable.
- The `bootstrap/cluster-age.key.sops` file is the one exception: it has only the 2 YubiKeys as recipients (the cluster key can't decrypt itself).

### 7.3 `.sops.yaml`

```yaml
creation_rules:
  - path_regex: clusters/.*\.sops\.(yaml|json)$
    age: >-
      age1yubikey1primary...,
      age1yubikey1backup...,
      age1cluster...
  # Tailscale auth key: consumed by tofu apply, never by Flux, so YubiKeys only.
  - path_regex: talos/tailscale-authkey\.sops\.txt$
    age: >-
      age1yubikey1primary...,
      age1yubikey1backup...
  # Tofu state passphrase: YubiKeys only — Flux never runs tofu.
  - path_regex: tofu/encryption-passphrase\.sops\.txt$
    age: >-
      age1yubikey1primary...,
      age1yubikey1backup...
  # Cluster software age key: YubiKeys only — it can't decrypt itself.
  - path_regex: bootstrap/cluster-age\.key\.sops$
    age: >-
      age1yubikey1primary...,
      age1yubikey1backup...
```

### 7.4 Operator workflow

Edit an encrypted file: `sops clusters/frodo/infrastructure/controllers/grafana/admin.sops.yaml` → YubiKey prompts for touch → file opens decrypted in `$EDITOR` → save → sops re-encrypts to all recipients → `git diff` shows only the encrypted blob changed → commit.

Add a new secret: `sops -e -i <new-file>.sops.yaml` (encrypts from scratch using `.sops.yaml` recipient rules).

### 7.5 What lives where

| Secret | Path | Notes |
|---|---|---|
| Tofu state encryption passphrase | `tofu/encryption-passphrase.sops.txt` | Encrypted to YubiKeys only; not in cluster at all |
| Cluster software age key | `bootstrap/cluster-age.key.sops` | Encrypted to YubiKeys only |
| Talos PKI + etcd encryption key | Inside tofu state | Generated by `hcloud-talos` module on first apply; protected by state encryption (§5.1) |
| Tailscale auth key | `talos/tailscale-authkey.sops.txt` | Decrypted at apply time, exported as `TF_VAR_tailscale_auth_key`, consumed by the module's `tailscale` input |
| Cloudflare tunnel token | `clusters/frodo/infrastructure/controllers/cloudflared/tunnel-token.sops.yaml` | Output of tofu, piped through sops (§6.B step 4) |

Phase 2 (§16) adds secrets for the backup bucket, ntfy topic URL, Grafana admin, Renovate PAT, and the hcloud-ccm API token. All follow the same `*.sops.yaml` convention.

### 7.6 YubiKey rotation (documented in `docs/secrets.md`)

Adding a new YubiKey (e.g., replacing a lost backup):
1. `age-plugin-yubikey --generate --slot 1 --touch-policy cached` on the new YubiKey
2. Update `.sops.yaml` with the new public key, remove the lost one
3. `sops updatekeys <file>` on every `*.sops.yaml` — re-wraps the data key to the new recipient set without re-encrypting the payload
4. Commit

This is a single PR touching every encrypted file in the repo, which is why CI validates SOPS sanity and runs gitleaks on every PR (§10): a botched `updatekeys` or a stray plaintext slip gets caught before merge.

### 7.7 Disaster recovery from YubiKey alone

If the entire cluster is lost and the laptop is lost:
1. Clone the repo to a new laptop
2. Install `sops`, `age`, `age-plugin-yubikey`, `mise`, `tofu`, `talosctl`, `flux`, `kubectl`
3. Plug in either YubiKey (primary or backup)
4. Run §6.B end-to-end. The YubiKey touch at step 3 unwraps `tofu/encryption-passphrase.sops.txt` to decrypt state; the YubiKey touch at step 6 decrypts `bootstrap/cluster-age.key.sops` to install the `sops-age` secret.

The YubiKey is the only out-of-band artifact. Everything else is in git.

---

## 8. Networking

Two separate planes: **public ingress** (HTTP apps) and **admin access** (talosctl/kubectl).

### 8.1 Public ingress — Cloudflare Tunnel

```
browser → cloudflare edge → cloudflared tunnel → cloudflared pod
       → traefik svc (ClusterIP) → traefik pod → app svc → app pod
```

- **No HTTP ports open on the server.** cloudflared makes an outbound connection from inside the cluster; nothing public-facing is bound on the Hetzner NIC.
- **Real client IP** arrives in `Cf-Connecting-Ip`. If ever needed, install the Traefik Cloudflare source-IP plugin. Not bothered with yet.

### 8.2 Admin access — Tailscale

```
laptop/phone (tailnet)  ─┐
                         ├→ frodo.<tailnet>.ts.net → tailscaled (Talos extension)
another operator         ─┘     │
                                ├→ talosctl (localhost:50000 inside Talos)
                                └→ kube-apiserver (:6443)
```

- Hetzner firewall on `frodo`: **only port 22/TCP open** (break-glass via Hetzner rescue, not normal operations). 6443 and 50000 are **closed to the public internet entirely**.
- `tailscaled` runs as a Talos system extension (`siderolabs/tailscale`), joined via a pre-authorized auth key embedded in machineconfig at bootstrap.
- `kubeconfig` and `talosconfig` both reference `https://frodo.<tailnet>.ts.net:<port>`, so they work from any laptop/phone signed into the tailnet without IP juggling.
- Future: add private services (personal dashboards, internal tools) on in-cluster ClusterIP services, exposed via Tailscale subnet router or a second Ingress class — no Cloudflare exposure needed.
- **No SSH** anywhere. Debugging is via `talosctl dmesg`, `talosctl logs`, `talosctl reset` over the Tailscale mesh.

### 8.3 Trust dependency

Cluster admin access depends on Tailscale Inc. being up. If Tailscale control plane is down, you can't reach talosctl/kubectl. Mitigations:
- `tailscale login` sessions on laptop + phone are cached and work without the coordinator for ~24 h.
- Hetzner console gives root-level rescue access independent of Tailscale for true emergencies.
- Long-term escape hatch: swap to self-hosted **Headscale** (same Tailscale clients, different coordinator). No code changes on Talos side.

---

## 9. Storage

One StorageClass, one path, one physical device. Deliberate — single-node cluster means no topology constraints, no CSI, no snapshots, no replication.

### 9.1 The data path

```
Hetzner Volume (40 GB ext4)
  └─ mounted at /var/mnt/data on the Talos host (machine.disks in machineconfig)
       └─ bound into kubelet via machine.kubelet.extraMounts
            └─ /var/mnt/data/local-path-provisioner/<namespace>_<pvc>/
                 └─ bind-mounted into pods as PVC volumes
```

The Hetzner Volume is the single durable surface. Everything that matters on disk lives under `/var/mnt/data`:

| Path | Owner |
|---|---|
| `/var/mnt/data/local-path-provisioner/` | `local-path-provisioner` PVCs (empty at v1; phase 2 adds victoria-metrics, victoria-logs, grafana, postgres) |
| `/var/mnt/data/etcd/` *(optional)* | If etcd ever needs to be moved off the root disk — not today. |

The Talos root disk (80 GB NVMe from the CAX21) holds the OS image, container images, and etcd. Losing the root disk means "rebuild the server" (§6.B). At v1 there is no PVC data on the volume at all — losing it is a no-op for user state. Phase 2 (§16) introduces real stateful data (Postgres), which gets its own Barman/S3 recovery path. Two independent blast radii.

### 9.2 local-path-provisioner config

```yaml
# clusters/frodo/infrastructure/controllers/local-path-provisioner/values.yaml
storageClass:
  defaultClass: true
  name: local-path
  reclaimPolicy: Retain
nodePathMap:
  - node: DEFAULT_PATH_FOR_NON_LISTED_NODES
    paths:
      - /var/mnt/data/local-path-provisioner
```

- **`defaultClass: true`** — any PVC without `storageClassName` lands here. No workload should need to know the provisioner exists.
- **`reclaimPolicy: Retain`** — deleting a PVC leaves the directory on disk. Velero-restore-after-accidental-delete is still possible as long as the directory isn't manually wiped. The operator GCs unwanted directories by hand during quarterly cleanups.
- **No `pathPattern`** — default naming (`<namespace>_<pvc>_<uid>/`) is fine. Predictable enough to find in a restic bucket listing.

### 9.3 What this gives up

- **No CSI snapshots.** `local-path-provisioner` doesn't implement the CSI snapshot interface, so volsync / k8up / kasten are out. Phase 2 (§16) uses CNPG's Barman/S3 integration for Postgres and optional Velero FSB for anything non-Postgres — both backup paths that work against any filesystem.
- **No ReadWriteMany.** Single node, single writer per PVC. Not a problem on a single-node cluster.
- **No automatic resize.** Resizing means: stop the pod, resize the underlying directory (it's just a bind mount of ext4, so the "volume" is implicit), restart. The Hetzner Volume itself can be resized online via `tofu apply` + `resize2fs` in a Talos maintenance task.
- **No topology/zonal concerns.** There's one node.

The tradeoff is explicit: give up all cloud-native storage features, gain a 15 MB controller and zero operational overhead. Right sizing for a single-node personal cluster.

### 9.4 Volume durability

The Hetzner Volume is declared with `prevent_destroy = true` in tofu (§5.3), so `tofu destroy` refuses to delete it. Server replacement reuses the same volume by re-attaching to the fresh Talos instance — the UUID stays stable, `/var/mnt/data` is on the same bytes, PVC data survives untouched. The only volume-loss events that matter:

1. **Hetzner DC fire.** Out of scope at v1 (no data on the volume at all; the rebuild path alone covers full recovery). Phase 2 (§16) adds CNPG/Barman PITR to `raveh-infra-backups`, which makes a full DC loss recoverable but slow.
2. **Operator typo.** `prevent_destroy` guards against this in tofu. Manual `hcloud volume delete` from the CLI is the remaining risk — mitigated by the Hetzner token being scoped to the one project.

---

## 10. CI — what GitHub Actions enforces on main

Under the assume-public threat model (§1), CI is the second layer beneath the pre-commit hook: anything a sleep-deprived future me skips locally gets caught here before merge. Four jobs, all required for `main`:

`.github/workflows/validate.yaml`:

```yaml
name: validate
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  gitleaks:
    # Plaintext secret scan on the full diff. Mirrors the pre-commit hook
    # exactly so a bypassed `--no-verify` commit still fails CI.
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITLEAKS_CONFIG: .gitleaks.toml

  sops-sanity:
    # Fail if any *.sops.yaml has plaintext `data:` fields, or any file
    # matching .sops.yaml recipient rules isn't actually encrypted.
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/ci/sops-sanity.sh

  flux-build:
    # `flux build kustomization` for each cluster path. Catches broken
    # dependsOn, missing substitutions, malformed HelmRelease values before
    # the controller sees them.
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: fluxcd/flux2/action@main
      - run: flux build kustomization infrastructure --path=clusters/frodo --dry-run
      - run: flux build kustomization apps --path=clusters/frodo --dry-run

  tofu-validate:
    # fmt + validate only. No plan in CI — plan needs the encryption
    # passphrase + cloud credentials, which are operator-local.
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - run: tofu -chdir=tofu fmt -check -recursive
      - run: tofu -chdir=tofu validate
```

Branch protection on `main`: all four jobs required green, no force-push, no admin bypass, linear history. Because Flux pulls, a broken `main` halts reconciliation cluster-wide — CI is the only safety net between a bad commit and a dead cluster. Phase 2 (§16) adds a `kubeconform` job once there are enough manifests + CRDs for schema validation to catch things `flux build` misses.

**Not in CI:** `tofu plan`. Plan needs the state encryption passphrase and live cloud credentials; both are operator-local and never touch a runner. Plan happens on the laptop via `mise run tofu-plan`.

---

## 11. Observability

**Deferred to phase 2 (§16).** At v1 there is nothing to observe: one node, zero apps, no user traffic. The full stack — `victoria-metrics-k8s-stack` + `victoria-logs-single` + Grafana Alloy + ntfy.sh alerting, per §0.6/§0.7 — lands alongside the first real app. Until then, `kubectl logs` + `talosctl dmesg` over the Tailscale mesh are enough.

What's preserved for phase 2: the choice of VictoriaMetrics as the single vendor, ntfy as the alert receiver, Alloy as the log shipper, and a ~750 MB total RSS budget (already carved out of the §3.1 headroom).

---

## 12. Backups

**Deferred to phase 2 (§16).** At v1 there is no data worth backing up at all: no `apps/` subtree, no PVCs in use, every component rebuilds from git via §6.B.

Phase 2 adds backups *targeted at what actually has state* — Postgres via CloudNativePG's built-in Barman/S3 integration (PITR + base backups to `raveh-infra-backups`), and optionally Velero with File System Backup for any non-Postgres PVCs. Velero is not preordained: if the fullstack app puts all its state in Postgres, Velero is skipped entirely. The quarterly restore drill only makes sense once there's a non-trivial restore path to verify.

---

## 13. Dependency automation

**Deferred to phase 2 (§16).** At v1 the set of versioned things is tiny (Talos installer image, Flux controllers, a handful of Helm charts for cloudflared + Traefik + local-path-provisioner). Manual `flux reconcile` + quarterly touch-up is cheaper than operating Renovate on a nearly-static tree.

Phase 2 turns on Renovate as a `CronJob` in-cluster once the controller set grows: weekends-only schedule, `prConcurrentLimit: 5`, patch auto-merge via GitHub `platformAutomerge`, careful-upgrade labels on `ghcr.io/siderolabs/installer`, `ghcr.io/fluxcd/` prefix, and `matchManagers: ["flux", "kubernetes"]` for k8s minor/major. Config already drafted; committing it before there's something to update would just generate noise.

---

## 14. Disaster recovery — full rebuild

The full-rebuild path is **§6.B**. DR is not a separate procedure — the every-rebuild path is written to double as the DR path, because the only way to verify DR still works is to use it regularly. Every time you rebuild frodo for any reason, you're drilling DR.

At v1 there is no stateful data to restore. Every component — Talos, Flux, cloudflared, Traefik, local-path-provisioner — rebuilds from git alone, and there are no PVCs bound to any user-facing app. DR is literally "§6.B end-to-end." Phase 2 (§16) introduces Postgres, and with it a real data-restore path via CNPG's Barman/S3 integration; DR becomes "§6.B + CNPG point-in-time recovery from `raveh-infra-backups`."

**Single points of failure at v1 (none of which §6.B can rebuild on its own):**

| SPOF | Backup strategy | What happens if lost |
|---|---|---|
| Tofu state bucket (`raveh-infra-tfstate`) | Hetzner Object Storage versioning **on**; quarterly `aws s3 sync` to a second bucket once it exists | `tofu import` can rebuild state from live cloud resources, but it's a painful day. Don't lose state. |
| Both YubiKeys | Primary on keychain, backup in a physical safe offsite. Never travel with both. | Total cryptographic loss. Every encrypted file in the repo becomes permanent ciphertext. No recovery path. §7.1 out-of-scope. |
| GitHub repo | `git clone --mirror` to an offline drive monthly. GitHub org/account suspension is the realistic threat, not git corruption. | Repo is the source of truth. Without it, there's nothing to bootstrap from. |

The order of loss matters: losing the state bucket is "a painful afternoon"; losing the repo is "a painful week"; losing both YubiKeys is "I start over from scratch with new cryptographic roots."

---

## 15. Migration from current Komodo setup

Per §0.3: **big-bang replace**. Nuke the current Komodo VM, stand up the Talos cluster from scratch. Because v1 hosts no user-facing apps, there is nothing on the current stack worth porting — Gatus history included. The current `status.raveh.dev` page goes away and does not come back until phase 2 decides on a status-page approach (likely an external checker; see §2/§16). Estimated downtime: ~20 min during cutover, all of it on `status.raveh.dev` and `komodo.raveh.dev` (neither is load-bearing).

### 15.1 Pre-flight

1. **Archive current tree.** `git checkout -b archive/komodo && git push -u origin archive/komodo`. Tag as `v0-komodo`. This is the escape hatch — `git checkout v0-komodo && tofu apply` from inside `archive/komodo` restores the old world.
2. **Record the current tofu state** for the old stack (`tofu state pull > /tmp/komodo-state.json` into `archive/komodo`) so you can restore it locally if the remote state is rewritten before you expect.

### 15.2 Cutover

1. On `main`: rewrite the repo per §4 — delete `komodo/`, `stacks/`, and the old `tofu/` contents, write the new layout. All changes land on a single branch `feat/talos`.
2. Green CI on `feat/talos` (§10 gates). Merge to `main`.
3. **Run §6.A once** if this is the first time any of the bootstrap artifacts (`tofu/encryption-passphrase.sops.txt`, `bootstrap/cluster-age.key.sops`, `talos/tailscale-authkey.sops.txt`) have been generated. They live in git after this, so subsequent rebuilds skip straight to §6.B.
4. **Tear down the old stack.** From a checkout of `archive/komodo`: `tofu destroy`. This removes the old frodo VM, the old Hetzner volume (yes, deliberately — new design uses a fresh volume), and releases the Cloudflare DNS records so the new tofu run can claim them cleanly.
5. **Stand up the new stack.** Back on `main`: run **§6.B end-to-end**. At step 7 (Flux reconciled `infrastructure/`), the platform is up: Traefik returns 404 for every host via the tunnel, which is the expected v1 end state.
6. Verify per §6.B step 8. Total downtime from step 4 to here: ~20 min, dominated by Talos install + Flux first reconcile.

### 15.3 Rollback

If anything goes sideways, the old stack is one command away: `git checkout v0-komodo && tofu apply` from inside `archive/komodo`. The `v0-komodo` tag and the local state snapshot from step 15.1.2 are the two pieces that make this safe. There is no "point of no return" in this cutover — nothing on the new stack holds data, so rolling back is symmetric with rolling forward.

---

## 16. Phase 2 — app bring-up

Phase 2 is the PR (or small PR series) that lands **alongside the first real app** — a Vue + FastAPI + Postgres fullstack project. Everything here was deliberately deferred from v1 (§2.2) because the cost of adding it later is a single Flux reconcile, and the benefit of *not* running it on an empty cluster is real RAM, real toolchain, and real operator attention.

Phase 2 is **purely additive**. No v1 component is replaced or restructured — the repo layout in §4 grows new directories, existing files stay as they are.

### 16.1 Scope

| Component | Why now (not at v1) | Where it lands |
|---|---|---|
| **hcloud-ccm** | Only needed when something actually calls the Hetzner API from inside the cluster (LoadBalancer services, typed node labels). Doesn't exist at v1. | `clusters/frodo/infrastructure/controllers/hcloud-ccm/` + `talos/patches/hetzner-ccm-args.yaml` + secret from `.env` |
| **CloudNativePG operator + `Cluster`** | The app needs Postgres. CNPG gives PITR, Barman/S3 backups, a Grafana dashboard, and an operator that actually understands PG replication and failover — at a cost the single node can afford (~150 MB operator + ~200 MB PG instance for a small schema). | `clusters/frodo/infrastructure/controllers/cnpg-operator/` + `clusters/frodo/apps/<name>/postgres/cluster.yaml` referencing the bucket from §0.9 |
| **victoria-metrics-k8s-stack + victoria-logs-single + Alloy + ntfy.sh alerting** | Once the app is in front of real traffic, blind operation stops being acceptable. Alerts go to the phone via ntfy per §0.7. Content pre-specced in the old §11 (kept in git history). | `clusters/frodo/infrastructure/controllers/{victoria-metrics,victoria-logs,grafana,alloy}/` + `vmrules.yaml` + `ntfy-receiver.sops.yaml` |
| **External status page** | If we still want a `status.raveh.dev` at phase 2, use an **external** uptime checker (Healthchecks.io, Better Stack, or a Cloudflare Worker on a cron) rather than in-cluster. In-cluster status pages share fate with the thing they monitor. | External SaaS + a Cloudflare Worker or DNS-only record, zero in-cluster footprint |
| **Cloudflare Access for Grafana** | Phase 2 is when Grafana exists, so this is when its Access app lands. | `tofu/cloudflare.tf` — add `cloudflare_zero_trust_access_application` "grafana" with the allowlist from §0.10 |
| **Velero (FSB), optional** | Only needed if any non-Postgres PVC ends up with state worth restoring. CNPG+Barman already covers Postgres; if the fullstack app keeps everything else in PG, Velero is skipped entirely. | `clusters/frodo/infrastructure/controllers/velero/` + scoped S3 cred in SOPS. Decision gate: "does anything outside Postgres hold state?" |
| **Renovate** | Weekend-only CronJob. Turns on once there are enough pinned versions that manual upkeep is more annoying than PR triage. | `clusters/frodo/infrastructure/controllers/renovate/` + `renovate.json` at repo root + `github-token.sops.yaml` |
| **`kubeconform` CI job** | Catches schema errors that `flux build` misses once the manifest set is large enough for the difference to matter. | New job in `.github/workflows/validate.yaml` + `scripts/ci/kubeconform.sh` + `kubeconform` added to `mise.toml` |
| **The fullstack app itself** | The reason phase 2 exists. A new `apps/` subtree lands here for the first time. | `clusters/frodo/apps/<name>/` — Kustomization referencing a Vue static build (NGINX container) + FastAPI Deployment + CNPG `Cluster` + `IngressRoute` objects for Traefik |

### 16.2 Order

1. **Merge phase 2 infrastructure first**, in one PR or a short chain: hcloud-ccm + CNPG operator + observability stack + Renovate. Traefik and cloudflared stay exactly as they are from v1 — no tofu or tunnel changes. CI stays green because everything is additive.
2. **Add the `apps/` Kustomization** for the first time, plus the app's `Cluster` + Deployments + Services + `IngressRoute`s under `apps/<name>/`. Flux reconciles. CNPG provisions Postgres, Barman starts streaming WAL to the bucket. Traefik picks up the new `IngressRoute` and the app's subdomain lights up — the tunnel config never changes.
3. **Add the Cloudflare Access app for Grafana** in the same or a following tofu apply.
4. **Run the first restore drill** per §12 (now un-deferred): delete the app namespace's PVC or force a PITR, confirm the data comes back.

### 16.3 Budget

Against the §3.1 headroom (~6.4 GB free at v1), phase 2 consumes roughly:

| Component | RSS |
|---|---|
| hcloud-ccm | ~40 MB |
| CNPG operator + one small `Cluster` | ~350 MB |
| victoria-metrics-k8s-stack (VM + Grafana + vmagent + vmalert + vmalertmanager) | ~500 MB |
| victoria-logs-single | ~100 MB |
| Grafana Alloy DaemonSet | ~150 MB |
| Renovate CronJob (only runs on schedule) | ~0 MB steady |
| Velero (if any) | ~80 MB |
| **Phase 2 platform total** | **~1.2 GB** |
| **Remaining headroom for the Vue + FastAPI app** | **~5 GB** |

Comfortable on CAX21 (4 vCPU / 8 GB). If the app itself grows beyond ~2 GB RSS, the CAX31 upgrade (8 vCPU / 16 GB, ~€12/mo) is one `tofu apply` away.

### 16.4 Cross-references

Phase 2 turns on deferred decisions from §0 that v1 doesn't exercise:

- **§0.6** — declarative observability via HelmRelease values (Grafana dashboards as ConfigMaps picked up by the sidecar, never UI clicks).
- **§0.7** — vmalertmanager → ntfy.sh webhook receiver.
- **§0.9** — the scoped backup credential and the no-`s3:DeleteObject` bucket policy. Bucket created in phase 2, not v1.
- **§0.10** — email-allowlist Access app for Grafana (Cloudflare Access SSO).
- **§11/§12/§13** — the deferred-stub sections in v1 are replaced in the phase 2 PR with the actual controller manifests and drafts already retained in git history.

---

## 17. Known tradeoffs

- **Single-node = SPOF.** Accept ~5 min of downtime during Hetzner host maintenance (~1×/year).
- **YubiKey as trust root.** Hardware requirement for daily operations. Without the YubiKey, you cannot edit any encrypted file. Lost backup YubiKey = you are one YubiKey death from a full disaster recovery drill.
- **Talos has no SSH.** Behavior shift vs today. Debugging is via `talosctl`; dmesg/logs/reset are the tools. No more "just SSH in and fix it."
- **Tailscale coordinator is a third-party trust dependency.** Admin access goes through `tailscaled`. Mitigated by cached sessions, Hetzner console as break-glass, and Headscale as a future swap (§8.3).
- **Tofu → SOPS handoff has one manual piping step.** §6.B step 4 (`mise run tofu-secrets-sync`). Automated in a mise task but still a bespoke bit: every rebuild generates a fresh Cloudflare tunnel token, which has to be piped through SOPS and committed before Flux can reconcile cloudflared.
- **v1 is observability-blind.** No metrics, no logs, no alerts until phase 2. Acceptable because v1 runs almost nothing user-facing; unacceptable the moment a real app lands, which is exactly when §16 kicks in.
- **v1 has no backups.** Same reasoning — nothing to back up. Phase 2 adds CNPG/Barman the same day Postgres exists.
- **No cert-manager.** Follows from "Cloudflare terminates TLS and origin hop is in-cluster." If we ever need real TLS at the origin, add cert-manager + Cloudflare DNS01.

---

## 18. Explicitly not in scope

- MetalLB (cloudflared is the edge, no LB IP pool needed)
- cert-manager (no origin TLS)
- ExternalDNS (DNS in tofu, not k8s)
- Sealed Secrets (SOPS covers it)
- ArgoCD (Flux chosen)
- Cilium (Flannel is enough without NetworkPolicy)
- HA etcd / multi control plane (explicit single-node choice)
- kube-prometheus-stack (too heavy — phase 2 picks VictoriaMetrics instead)
- Longhorn / Ceph / replicated storage (single node)
- Flux image automation controllers (Renovate handles it with less RAM in phase 2)
- **Distributed tracing (Tempo, Jaeger, VictoriaTraces).** Alloy is OTel-native so the pipe is ready once phase 2 lands it, but no trace backend is deployed. When an app with real request flow arrives, add `victoria-traces` or Tempo as a sibling HelmRelease — no new shipper needed.
- **Service mesh (Istio, Linkerd, Cilium CNI).** Pointless on a single node — every pod-to-pod hop is localhost. Revisit only if the cluster grows beyond one node, which contradicts §0 anyway.
