resource "cloudflare_notification_policy" "tunnel_health" {
  provider   = cloudflare.account
  account_id = local.cloudflare_account_id
  name       = "Tunnel health"
  alert_type = "tunnel_health_event"
  enabled    = true

  mechanisms = {
    email = [{ id = var.cloudflare_proton_email }]
  }

  filters = {
    tunnel_id = [cloudflare_zero_trust_tunnel_cloudflared.shire.id]
  }
}

resource "cloudflare_notification_policy" "universal_ssl" {
  provider   = cloudflare.account
  account_id = local.cloudflare_account_id
  name       = "Universal SSL certificates"
  alert_type = "universal_ssl_event_type"
  enabled    = true

  mechanisms = {
    email = [{ id = var.cloudflare_proton_email }]
  }
}

resource "cloudflare_ct_alerting" "raveh_dev" {
  zone_id = local.cloudflare_zone_id
  enabled = true
  emails  = [var.cloudflare_proton_email]
}

import {
  to = cloudflare_ct_alerting.raveh_dev
  id = local.cloudflare_zone_id
}
