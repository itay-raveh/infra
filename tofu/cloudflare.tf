resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "shire" {
  account_id = var.cloudflare_account_id
  name       = local.cluster_name
  secret     = random_id.tunnel_secret.b64_std
  # API-managed config (required for the *_config resource below to work).
  config_src = "cloudflare"
}

# One dumb wildcard rule: every request goes to in-cluster Traefik, which
# owns host-header routing. Adding a new app is then a pure in-cluster
# change with no tofu run. The http_status:404 entry is the catch-all
# Cloudflare requires as the final ingress rule.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "shire" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.shire.id

  config {
    ingress_rule {
      service = "http://traefik.traefik.svc.cluster.local:80"
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}

# ttl=1 means "automatic", required for proxied records.
resource "cloudflare_record" "tunnel" {
  for_each = toset(["@", "*"])
  zone_id  = var.cloudflare_zone_id
  name     = each.key
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.shire.id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}
