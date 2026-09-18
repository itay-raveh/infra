resource "cloudflare_web_analytics_site" "raveh_dev" {
  provider = cloudflare.web_analytics

  account_id   = var.account_id
  auto_install = true
  enabled      = true
  zone_tag     = var.zone_id
}
