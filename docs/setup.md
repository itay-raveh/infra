# Setup

From zero to running server.

## Prerequisites

- [mise](https://mise.jdx.dev/) installed
- SSH key at `~/.ssh/id_ed25519`
- Hetzner Cloud account + API token
- Cloudflare account managing your domain, with Zero Trust enabled (free plan is fine)
- Hetzner Object Storage bucket for tofu state (see step 1)

## Steps

### 1. Create a state bucket

In Hetzner Cloud Console, create an Object Storage bucket (e.g. `raveh-infra-tfstate` in `eu-central`). Generate S3 credentials for it.

### 2. Create a Cloudflare API token

Zone → raveh.dev: `Zone:Read`, `DNS:Edit`
Account → your account: `Cloudflare Tunnel:Edit`, `Access: Apps and Policies:Edit`

Grab your Cloudflare account ID from the Zero Trust dashboard sidebar.

### 3. Configure credentials

```bash
cp .env.example .env
```

Fill in the S3 credentials, Hetzner + Cloudflare API tokens, Cloudflare zone and account IDs, and state encryption passphrase.

### 4. Provision

```bash
mise install
mise run apply
```

Takes ~5 minutes. Tofu creates the server and the Cloudflare Tunnel, cloud-init mounts the volume, installs Dokploy, and connects `cloudflared` to the tunnel. DNS for the apex, wildcard, and `dokploy.raveh.dev` all point at the tunnel.

### 5. Configure Dokploy

Open [https://dokploy.raveh.dev](https://dokploy.raveh.dev). Cloudflare Access will challenge you  - sign in with the admin email from `tofu/variables.tf`. Then create a Dokploy admin account and configure:

1. **Server domain**  - Settings > Web Server, set to `dokploy.raveh.dev`. Leave "HTTPS Automatically provision SSL Certificate" **off**  - Cloudflare terminates TLS at the edge, the tunnel carries plain HTTP on localhost.
2. **Docker cleanup**  - Settings > Server, enable daily cleanup.
3. **2FA**  - Profile settings, enable TOTP (set the Issuer to something like `Dokploy Frodo` so it's identifiable in your authenticator app).
4. **GitHub**  - Settings > Git, connect your GitHub account (OAuth flow). Webhooks land on `dokploy.raveh.dev/api/deploy/*`, which is a Cloudflare Access bypass, so GitHub can reach them without authentication.

### 6. Deploy a project

Create a project, add a Compose service, and point it at a Git repo with a `docker-compose.yml`. See [deploying.md](deploying.md).

## Break-glass access

If Cloudflare Access or the tunnel is down, SSH into the server directly and open a local tunnel to the panel:

```bash
mise run tunnel
```

Then open [http://localhost:3000](http://localhost:3000). SSH stays open on the firewall precisely for this.
