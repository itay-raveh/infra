moved {
  from = cloudflare_record.tunnel
  to   = cloudflare_dns_record.tunnel
}

moved {
  from = cloudflare_zone_dnssec.raveh_dev
  to   = module.cloudflare.cloudflare_zone_dnssec.raveh_dev
}

moved {
  from = cloudflare_zone_setting.min_tls_version
  to   = module.cloudflare.cloudflare_zone_setting.min_tls_version
}

moved {
  from = random_id.tunnel_secret
  to   = module.cloudflare.random_id.tunnel_secret
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.shire
  to   = module.cloudflare.cloudflare_zero_trust_tunnel_cloudflared.shire
}

moved {
  from = data.cloudflare_zero_trust_tunnel_cloudflared_token.shire
  to   = module.cloudflare.data.cloudflare_zero_trust_tunnel_cloudflared_token.shire
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.shire
  to   = module.cloudflare.cloudflare_zero_trust_tunnel_cloudflared_config.shire
}

moved {
  from = cloudflare_dns_record.tunnel
  to   = module.cloudflare.cloudflare_dns_record.tunnel
}

moved {
  from = cloudflare_ruleset.redirect_apex_to_itay
  to   = module.cloudflare.cloudflare_ruleset.redirect_apex_to_itay
}

moved {
  from = cloudflare_account_member.admin
  to   = module.cloudflare.cloudflare_account_member.admin
}

moved {
  from = cloudflare_account.raveh_dev
  to   = module.cloudflare.cloudflare_account.raveh_dev
}

moved {
  from = cloudflare_bot_management.raveh_dev
  to   = module.cloudflare.cloudflare_bot_management.raveh_dev
}

moved {
  from = cloudflare_dns_record.spf
  to   = module.cloudflare.cloudflare_dns_record.spf
}

moved {
  from = cloudflare_dns_record.proton_dkim
  to   = module.cloudflare.cloudflare_dns_record.proton_dkim
}

moved {
  from = cloudflare_dns_record.dmarc
  to   = module.cloudflare.cloudflare_dns_record.dmarc
}

moved {
  from = cloudflare_notification_policy.tunnel_health
  to   = module.cloudflare.cloudflare_notification_policy.tunnel_health
}

moved {
  from = cloudflare_notification_policy.universal_ssl
  to   = module.cloudflare.cloudflare_notification_policy.universal_ssl
}

moved {
  from = cloudflare_ct_alerting.raveh_dev
  to   = module.cloudflare.cloudflare_ct_alerting.raveh_dev
}

moved {
  from = cloudflare_ruleset.rate_limits
  to   = module.cloudflare.cloudflare_ruleset.rate_limits
}

moved {
  from = cloudflare_zone_setting.ssl
  to   = module.cloudflare.cloudflare_zone_setting.ssl
}

moved {
  from = cloudflare_zone_setting.zero_rtt
  to   = module.cloudflare.cloudflare_zone_setting.zero_rtt
}

moved {
  from = cloudflare_zone_setting.https
  to   = module.cloudflare.cloudflare_zone_setting.https
}

moved {
  from = cloudflare_universal_ssl_setting.raveh_dev
  to   = module.cloudflare.cloudflare_universal_ssl_setting.raveh_dev
}

moved {
  from = cloudflare_worker.root
  to   = module.cloudflare.cloudflare_worker.root
}

moved {
  from = cloudflare_worker_version.root
  to   = module.cloudflare.cloudflare_worker_version.root
}

moved {
  from = cloudflare_workers_deployment.root
  to   = module.cloudflare.cloudflare_workers_deployment.root
}

moved {
  from = cloudflare_workers_route.root
  to   = module.cloudflare.cloudflare_workers_route.root
}

moved {
  from = cloudflare_workers_custom_domain.quizmon
  to   = module.cloudflare.cloudflare_workers_custom_domain.quizmon
}

moved {
  from = cloudflare_workers_custom_domain.itay
  to   = module.cloudflare.cloudflare_workers_custom_domain.itay
}

moved {
  from = cloudflare_web_analytics_site.raveh_dev
  to   = module.cloudflare.cloudflare_web_analytics_site.raveh_dev
}
