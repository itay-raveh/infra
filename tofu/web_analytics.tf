resource "cloudflare_web_analytics_site" "raveh_dev" {
  provider = cloudflare.web_analytics

  account_id   = local.cloudflare_account_id
  auto_install = true
  enabled      = true
  zone_tag     = local.cloudflare_zone_id
}
