resource "cloudflare_ruleset" "rate_limits" {
  zone_id     = local.cloudflare_zone_id
  name        = "default"
  description = ""
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [{
    ref         = "48921219fe494971b9a4255ad4cec295"
    description = "Limit Google and Microsoft login requests"
    expression  = "http.request.uri.path in {\"/api/v1/auth/google\" \"/api/v1/auth/google/\" \"/api/v1/auth/microsoft\" \"/api/v1/auth/microsoft/\"}"
    action      = "block"
    enabled     = true
    ratelimit = {
      characteristics     = ["ip.src", "cf.colo.id"]
      period              = 10
      requests_per_period = 20
      mitigation_timeout  = 10
      requests_to_origin  = false
    }
  }]
}

import {
  to = cloudflare_ruleset.rate_limits
  id = "zones/${local.cloudflare_zone_id}/9e6085b9e0b9444fad5e458ae87a8386"
}
