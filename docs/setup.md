# Setup

From zero to running server.

## Prerequisites

- [mise](https://mise.jdx.dev/) installed
- SSH key at `~/.ssh/id_ed25519`
- Hetzner Cloud account + API token
- Cloudflare account managing your domain
- Hetzner Object Storage bucket for tofu state (see step 1)

## Steps

### 1. Create a state bucket

In Hetzner Cloud Console, create an Object Storage bucket (e.g. `raveh-infra-tfstate` in `eu-central`). Generate S3 credentials for it.

### 2. Configure credentials

```bash
cp .env.example .env
```

Fill in the S3 credentials, Hetzner and Cloudflare API tokens, and Cloudflare zone ID.

### 3. Provision

```bash
mise install
mise run apply
```

Takes ~5 minutes. Tofu creates the server, and cloud-init mounts the volume and installs Dokploy.

### 4. Access Dokploy

```bash
mise run tunnel
```

Open [http://localhost:3000](http://localhost:3000) and create an admin account.

### 5. Deploy a project

In Dokploy, create a project, add a Compose service, and point it at a Git repo with a `docker-compose.yml`.
