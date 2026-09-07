resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "shire" {
  account_id    = local.cloudflare_account_id
  name          = local.cluster_name
  tunnel_secret = random_id.tunnel_secret.b64_std
  # API-managed config (required for the *_config resource below to work).
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "shire" {
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.shire.id
}

# One dumb wildcard rule: every request goes to in-cluster Traefik, which
# owns host-header routing. Adding a new app is then a pure in-cluster
# change with no tofu run. The http_status:404 entry is the catch-all
# Cloudflare requires as the final ingress rule.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "shire" {
  account_id = local.cloudflare_account_id
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

# ttl=1 means "automatic", required for proxied records.
resource "cloudflare_dns_record" "tunnel" {
  for_each = toset(["@", "*"])
  zone_id  = local.cloudflare_zone_id
  name     = each.key
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.shire.id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}

resource "cloudflare_ruleset" "redirect_apex_to_itay" {
  depends_on = [cloudflare_workers_route.root]

  zone_id     = local.cloudflare_zone_id
  name        = "default"
  description = "Canonical hostname redirects"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [{
    ref         = "redirect_apex_to_itay"
    description = "Redirect raveh.dev to itay.raveh.dev"
    expression  = "http.host eq \"raveh.dev\" and not http.request.uri.path in {\"/privacy\" \"/privacy/\" \"/privacy.html\" \"/ads.txt\"}"
    action      = "redirect"
    action_parameters = {
      from_value = {
        target_url = {
          expression = "concat(\"https://itay.raveh.dev\", http.request.uri.path)"
        }
        status_code           = 301
        preserve_query_string = true
      }
    }
  }]
}

moved {
  from = cloudflare_record.tunnel
  to   = cloudflare_dns_record.tunnel
}
