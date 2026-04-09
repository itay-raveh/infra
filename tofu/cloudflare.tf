# DNS records for raveh.dev.
# Only manages records we create  - existing records (Email Routing, etc.) are untouched.

resource "cloudflare_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = "raveh.dev"
  content = hcloud_server.frodo.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1 # Auto (required when proxied)
}

resource "cloudflare_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.raveh.dev"
  content = hcloud_server.frodo.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1 # Auto (required when proxied)
}
