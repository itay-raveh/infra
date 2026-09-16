import {
  to = module.cloudflare.cloudflare_zone_dnssec.raveh_dev
  id = local.cloudflare_zone_id
}

import {
  to = module.cloudflare.cloudflare_zone_setting.min_tls_version
  id = "${local.cloudflare_zone_id}/min_tls_version"
}

import {
  for_each = {
    primary = "7f524edc14fa71b31bf7354b3bfff2f8"
    gmail   = "5d5d854979ee59a29a9e0fac2bc56c61"
    proton  = "286c43f303932ef8b8e72e60f48c2682"
  }

  to = module.cloudflare.cloudflare_account_member.admin[each.key]
  id = "${local.cloudflare_account_id}/${each.value}"
}

import {
  to = module.cloudflare.cloudflare_account.raveh_dev
  id = local.cloudflare_account_id
}

import {
  to = module.cloudflare.cloudflare_bot_management.raveh_dev
  id = local.cloudflare_zone_id
}

import {
  to = module.cloudflare.cloudflare_dns_record.spf
  id = "${local.cloudflare_zone_id}/b3c75e7cca270074a86622bf47c87e9b"
}

import {
  to = module.cloudflare.cloudflare_dns_record.dmarc
  id = "${local.cloudflare_zone_id}/f5efbfa02cf769401bb2b2ed9002fd94"
}

import {
  to = module.cloudflare.cloudflare_ct_alerting.raveh_dev
  id = local.cloudflare_zone_id
}

import {
  to = module.cloudflare.cloudflare_ruleset.rate_limits
  id = "zones/${local.cloudflare_zone_id}/9e6085b9e0b9444fad5e458ae87a8386"
}

import {
  to = module.cloudflare.cloudflare_zone_setting.ssl
  id = "${local.cloudflare_zone_id}/ssl"
}

import {
  to = module.cloudflare.cloudflare_zone_setting.zero_rtt
  id = "${local.cloudflare_zone_id}/0rtt"
}

import {
  for_each = toset(["always_use_https", "automatic_https_rewrites"])
  to       = module.cloudflare.cloudflare_zone_setting.https[each.key]
  id       = "${local.cloudflare_zone_id}/${each.key}"
}

import {
  to = module.cloudflare.cloudflare_universal_ssl_setting.raveh_dev
  id = local.cloudflare_zone_id
}
