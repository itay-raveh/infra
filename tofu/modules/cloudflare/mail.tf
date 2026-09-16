resource "cloudflare_dns_record" "spf" {
  zone_id = var.zone_id
  name    = "raveh.dev"
  type    = "TXT"
  content = "\"v=spf1 include:_spf.mx.cloudflare.net include:_spf.protonmail.ch ~all\""
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "proton_dkim" {
  for_each = {
    protonmail  = "protonmail.domainkey.d765izbpcszv2yfos6rnka6gnkd2a2jvfwku6raryfu5szt62vgpa.domains.proton.ch"
    protonmail2 = "protonmail2.domainkey.d765izbpcszv2yfos6rnka6gnkd2a2jvfwku6raryfu5szt62vgpa.domains.proton.ch"
    protonmail3 = "protonmail3.domainkey.d765izbpcszv2yfos6rnka6gnkd2a2jvfwku6raryfu5szt62vgpa.domains.proton.ch"
  }

  zone_id = var.zone_id
  name    = "${each.key}._domainkey.raveh.dev"
  type    = "CNAME"
  content = each.value
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "dmarc" {
  zone_id = var.zone_id
  name    = "_dmarc.raveh.dev"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:c594779370294b26b531a405c7c97fa5@dmarc-reports.cloudflare.net\""
  ttl     = 1
  proxied = false
}
