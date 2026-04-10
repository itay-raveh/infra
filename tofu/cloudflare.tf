# Cloudflare Tunnel + Access + DNS for raveh.dev.
#
# All ingress to frodo goes through the tunnel  - no public ports. The Komodo
# panel is gated by Cloudflare Access (identity-based SSO). Traefik handles
# routing for user-facing apps on *.raveh.dev.

# --- Tunnel ---

resource "random_id" "tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "frodo" {
  account_id = var.cloudflare_account_id
  name       = "frodo"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "frodo" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.frodo.id

  config {
    # Komodo panel  - Access-gated, routed directly to the Komodo Core container.
    ingress_rule {
      hostname = "komodo.raveh.dev"
      service  = "http://localhost:9120"
    }

    # User-facing apps  - Traefik handles per-host routing.
    ingress_rule {
      hostname = "raveh.dev"
      service  = "http://localhost:80"
    }
    ingress_rule {
      hostname = "*.raveh.dev"
      service  = "http://localhost:80"
    }

    # Catch-all.
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# --- DNS ---
#
# CNAMEs to the tunnel hostname. Cloudflare auto-flattens the apex CNAME to
# A/AAAA records at resolve time.

locals {
  tunnel_hostname = "${cloudflare_zero_trust_tunnel_cloudflared.frodo.id}.cfargotunnel.com"
}

resource "cloudflare_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = "raveh.dev"
  content = local.tunnel_hostname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.raveh.dev"
  content = local.tunnel_hostname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "komodo" {
  zone_id = var.cloudflare_zone_id
  name    = "komodo.raveh.dev"
  content = local.tunnel_hostname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# --- Access application: Komodo panel ---
#
# Two apps on the same host, matched by path specificity. The webhook listener
# path is a bypass (public) so GitHub can POST; everything else requires the
# admin email.

resource "cloudflare_zero_trust_access_application" "panel_webhooks" {
  account_id       = var.cloudflare_account_id
  name             = "Komodo webhooks"
  domain           = "komodo.raveh.dev/listener"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "panel_webhooks_bypass" {
  application_id = cloudflare_zero_trust_access_application.panel_webhooks.id
  account_id     = var.cloudflare_account_id
  name           = "Bypass (public webhooks)"
  precedence     = 1
  decision       = "bypass"

  include {
    everyone = true
  }
}

resource "cloudflare_zero_trust_access_application" "panel" {
  account_id       = var.cloudflare_account_id
  name             = "Komodo panel"
  domain           = "komodo.raveh.dev"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "panel_admin" {
  application_id = cloudflare_zero_trust_access_application.panel.id
  account_id     = var.cloudflare_account_id
  name           = "Allow admin"
  precedence     = 1
  decision       = "allow"

  include {
    email = [var.admin_email]
  }
}
