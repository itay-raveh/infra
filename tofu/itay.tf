resource "cloudflare_workers_custom_domain" "itay" {
  account_id = local.cloudflare_account_id
  hostname   = "itay.raveh.dev"
  service    = "itay"
  zone_id    = local.cloudflare_zone_id
}
