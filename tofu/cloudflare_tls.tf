resource "cloudflare_zone_setting" "ssl" {
  zone_id    = local.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

import {
  to = cloudflare_zone_setting.ssl
  id = "${local.cloudflare_zone_id}/ssl"
}

resource "cloudflare_zone_setting" "zero_rtt" {
  zone_id    = local.cloudflare_zone_id
  setting_id = "0rtt"
  value      = "off"
}

import {
  to = cloudflare_zone_setting.zero_rtt
  id = "${local.cloudflare_zone_id}/0rtt"
}

resource "cloudflare_zone_setting" "https" {
  for_each = toset(["always_use_https", "automatic_https_rewrites"])

  zone_id    = local.cloudflare_zone_id
  setting_id = each.key
  value      = "on"
}

import {
  for_each = cloudflare_zone_setting.https
  to       = cloudflare_zone_setting.https[each.key]
  id       = "${local.cloudflare_zone_id}/${each.key}"
}

resource "cloudflare_universal_ssl_setting" "raveh_dev" {
  zone_id = local.cloudflare_zone_id
  enabled = true
}

import {
  to = cloudflare_universal_ssl_setting.raveh_dev
  id = local.cloudflare_zone_id
}
