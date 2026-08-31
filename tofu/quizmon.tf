resource "cloudflare_workers_custom_domain" "quizmon" {
  account_id = local.cloudflare_account_id
  hostname   = "quizmon.raveh.dev"
  service    = "quizmon"
  zone_id    = local.cloudflare_zone_id
}
