resource "cloudflare_dns_record" "spf" {
  zone_id = local.cloudflare_zone_id
  name    = "raveh.dev"
  type    = "TXT"
  content = "\"v=spf1 include:_spf.mx.cloudflare.net include:_spf.protonmail.ch ~all\""
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.spf
  id = "${local.cloudflare_zone_id}/b3c75e7cca270074a86622bf47c87e9b"
}

resource "cloudflare_dns_record" "proton_dkim" {
  for_each = {
    protonmail  = "protonmail.domainkey.d765izbpcszv2yfos6rnka6gnkd2a2jvfwku6raryfu5szt62vgpa.domains.proton.ch"
    protonmail2 = "protonmail2.domainkey.d765izbpcszv2yfos6rnka6gnkd2a2jvfwku6raryfu5szt62vgpa.domains.proton.ch"
    protonmail3 = "protonmail3.domainkey.d765izbpcszv2yfos6rnka6gnkd2a2jvfwku6raryfu5szt62vgpa.domains.proton.ch"
  }

  zone_id = local.cloudflare_zone_id
  name    = "${each.key}._domainkey.raveh.dev"
  type    = "CNAME"
  content = each.value
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "dmarc" {
  zone_id = local.cloudflare_zone_id
  name    = "_dmarc.raveh.dev"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:c594779370294b26b531a405c7c97fa5@dmarc-reports.cloudflare.net\""
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.dmarc
  id = "${local.cloudflare_zone_id}/f5efbfa02cf769401bb2b2ed9002fd94"
}
