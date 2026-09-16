resource "cloudflare_bot_management" "raveh_dev" {
  zone_id                 = var.zone_id
  ai_bots_protection      = "block"
  content_bots_protection = "disabled"
  crawler_protection      = "enabled"
  enable_js               = false
  fight_mode              = false
  is_robots_txt_managed   = true
}
