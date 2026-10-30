resource "cloudflare_zone_dnssec" "raveh_dev" {
  zone_id = var.zone_id
  status  = "active"
}

# ttl=1 means "automatic", required for proxied records.
resource "cloudflare_dns_record" "tunnel" {
  for_each = toset(["@", "*"])
  zone_id  = var.zone_id
  name     = each.key
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.shire.id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}
