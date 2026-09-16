resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "shire" {
  account_id    = var.account_id
  name          = var.tunnel_name
  tunnel_secret = random_id.tunnel_secret.b64_std
  # API-managed config (required for the *_config resource below to work).
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "shire" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.shire.id
}

# Traefik routes application hostnames without per-app Tunnel rules.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "shire" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.shire.id

  config = {
    ingress = [
      {
        hostname = "*.raveh.dev"
        service  = "http://traefik.traefik.svc.cluster.local:80"
      },
      {
        hostname = "raveh.dev"
        service  = "http://traefik.traefik.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}
