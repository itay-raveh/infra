resource "cloudflare_bot_management" "raveh_dev" {
  zone_id                 = local.cloudflare_zone_id
  ai_bots_protection      = "block"
  cf_robots_variant       = "off"
  content_bots_protection = "disabled"
  crawler_protection      = "enabled"
  enable_js               = false
  fight_mode              = false
  is_robots_txt_managed   = true
}

import {
  to = cloudflare_bot_management.raveh_dev
  id = local.cloudflare_zone_id
}
