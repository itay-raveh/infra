moved {
  from = module.cloudflare.cloudflare_ruleset.redirect_apex_to_itay
  to   = cloudflare_ruleset.redirect_apex_to_itay
}

moved {
  from = module.cloudflare.cloudflare_worker.root
  to   = cloudflare_worker.root
}

moved {
  from = module.cloudflare.cloudflare_worker_version.root
  to   = cloudflare_worker_version.root
}

moved {
  from = module.cloudflare.cloudflare_workers_deployment.root
  to   = cloudflare_workers_deployment.root
}

moved {
  from = module.cloudflare.cloudflare_workers_route.root
  to   = cloudflare_workers_route.root
}

moved {
  from = module.cloudflare.cloudflare_workers_custom_domain.quizmon
  to   = cloudflare_workers_custom_domain.quizmon
}

moved {
  from = module.cloudflare.cloudflare_workers_custom_domain.itay
  to   = cloudflare_workers_custom_domain.itay
}
