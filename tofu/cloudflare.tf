# 32 bytes of entropy, base64-encoded, used as the tunnel's shared secret.
# Generated in tofu state so no human ever sees or rotates it by hand;
# the tunnel_token output below is what cloudflared actually consumes.
resource "random_id" "frodo_tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "frodo" {
  account_id = var.cloudflare_account_id
  name       = local.cluster_name
  secret     = random_id.frodo_tunnel_secret.b64_std
  config_src = "cloudflare"
}

# One dumb wildcard rule: every request goes to in-cluster Traefik, which
# owns host-header routing. Adding a new app is then a pure in-cluster
# change with no tofu run. The http_status:404 entry is the catch-all
# Cloudflare requires as the final ingress rule.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "frodo" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.frodo.id

  config {
    ingress_rule {
      service = "http://traefik.traefik.svc.cluster.local:80"
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Apex + wildcard CNAMEs both point at the tunnel. Proxied so traffic
# rides the Cloudflare edge into the tunnel rather than resolving to a
# direct origin. ttl=1 means "automatic", required for proxied records.
resource "cloudflare_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.frodo.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.frodo.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# Consumed post-apply by `mise run tofu-secrets-sync`, sops-encrypted
# into clusters/frodo/infrastructure/controllers/cloudflared/.
output "cloudflared_tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.frodo.tunnel_token
  sensitive = true
}
