resource "cloudflare_ruleset" "rate_limits" {
  zone_id     = var.zone_id
  name        = "default"
  description = ""
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = var.rate_limit_rules
}
