module "cloudflare" {
  source = "./modules/cloudflare"

  providers = {
    cloudflare               = cloudflare
    cloudflare.account       = cloudflare.account
    cloudflare.web_analytics = cloudflare.web_analytics
    random                   = random
  }

  account_id             = local.cloudflare_account_id
  zone_id                = local.cloudflare_zone_id
  tunnel_name            = local.cluster_name
  primary_email          = var.cloudflare_primary_email
  gmail_email            = var.cloudflare_gmail_email
  proton_email           = var.cloudflare_proton_email
  root_worker_source_dir = "${path.module}/../workers/root"
}
