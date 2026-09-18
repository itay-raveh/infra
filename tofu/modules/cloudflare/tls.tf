resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = var.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "zero_rtt" {
  zone_id    = var.zone_id
  setting_id = "0rtt"
  value      = "on"
}

resource "cloudflare_zone_setting" "https" {
  for_each = toset(["always_use_https", "automatic_https_rewrites"])

  zone_id    = var.zone_id
  setting_id = each.key
  value      = "on"
}

resource "cloudflare_universal_ssl_setting" "raveh_dev" {
  zone_id = var.zone_id
  enabled = true
}
