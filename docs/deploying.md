# Deploying a project

How to get a service running on `something.raveh.dev`.

## What a project needs

- An ARM64-compatible Docker image (`linux/arm64`)  - frodo is ARM
- A `docker-compose.yml`, either in a Git repo or pasted inline in Dokploy
- The Compose service attached to the `dokploy-network` (see below)

## Steps

1. Open [https://dokploy.raveh.dev](https://dokploy.raveh.dev), pass the Cloudflare Access challenge
2. Create a project, add a Compose service
3. Source: either a Git repo + branch, or **Raw** to paste the compose inline
4. **Domains tab**: add a domain (the source of truth for routing  - see below)
5. Deploy

If you connected GitHub during setup, Dokploy auto-deploys on push.

## Routing: use the Domains tab, not Traefik labels

Dokploy's Traefik mostly ignores `traefik.*` labels in raw-paste compose. The reliable path is the **Domains tab** on the service:

- **Host**: `myapp.raveh.dev`
- **Service Name**: must match the service key in your compose (e.g. `app`)
- **Port**: your container's port  - **the form pre-fills 3000, override it**
- **HTTPS**: **off**
- **Certificate Provider**: **None**

Cloudflare terminates TLS at the edge and the tunnel carries plain HTTP to Traefik, so Dokploy must not try to issue its own cert.

## Compose example

```yaml
services:
  app:
    image: ghcr.io/itay-raveh/my-project:main
    restart: unless-stopped
    networks:
      - dokploy-network
    volumes:
      - /mnt/data/my-project:/app/data

networks:
  dokploy-network:
    external: true
```

The `dokploy-network` declaration is required  - Dokploy's Traefik only sees containers attached to that network.

## Persistent data

Mount volumes under `/mnt/data/<project>` to survive redeployments. That path is the Hetzner persistent volume mounted by cloud-init.

## Secrets

Use Dokploy's environment variable management (per-service, in the UI). Don't put secrets in the compose file or this repo.

## Real client IP

Frodo sits behind Cloudflare → Cloudflare Tunnel → Traefik. By the time a request reaches your container, `X-Real-Ip` and `X-Forwarded-For` show the Docker bridge IP, not the visitor.

The real visitor IP is in the **`Cf-Connecting-Ip`** request header (set by Cloudflare). Apps that care about client IP should read that. There's no Traefik middleware to translate it because it would add complexity for a single-tenant personal infra and almost no app actually needs it.

## Backups

For services with databases or persistent data:

1. Set up an S3 destination in Settings → S3 Destinations (Cloudflare R2 works well)
2. Configure backup schedules per database in the service's Backups tab
3. For volume backups, use the Volume Backups section in the service settings

## Notifications

Set up a notification channel in Settings → Notifications to get alerts on build failures and backup errors. Supports Slack, Discord, email, and webhooks.
