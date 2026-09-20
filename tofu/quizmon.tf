resource "cloudflare_workers_custom_domain" "quizmon" {
  account_id = local.cloudflare_account_id
  hostname   = "quizmon.raveh.dev"
  service    = "quizmon"
  zone_id    = local.cloudflare_zone_id
}

locals {
  quizmon_database_host = "quizmon-db.raveh.dev"
  # Reserved in CNPG's additional primary Service, within the cluster's static IP range.
  quizmon_database_ip = "10.0.8.20"
}

variable "quizmon_hyperdrive_enabled" {
  type        = bool
  default     = true
  description = "Enable Quizmon Hyperdrive after its private database and public-CA certificate are ready."
}

resource "random_password" "quizmon_database" {
  for_each = toset(["quizmon", "powersync_source", "powersync_storage"])
  length   = 48
  special  = false
}

resource "random_password" "quizmon_auth" {
  length  = 64
  special = false
}

resource "cloudflare_dns_record" "quizmon_database" {
  zone_id = local.cloudflare_zone_id
  name    = local.quizmon_database_host
  type    = "A"
  content = local.quizmon_database_ip
  proxied = false
  ttl     = 300
}

resource "cloudflare_connectivity_directory_service" "quizmon_database" {
  account_id   = local.cloudflare_account_id
  name         = "quizmon-db"
  type         = "tcp"
  app_protocol = "postgresql"
  tcp_port     = 5432
  host = {
    hostname = local.quizmon_database_host
    resolver_network = {
      tunnel_id = module.cloudflare.tunnel_id
    }
  }
  tls_settings = {
    cert_verification_mode = "verify_full"
  }
  depends_on = [cloudflare_dns_record.quizmon_database]
}

resource "cloudflare_hyperdrive_config" "quizmon" {
  count      = var.quizmon_hyperdrive_enabled ? 1 : 0
  account_id = local.cloudflare_account_id
  name       = "quizmon"
  origin = {
    service_id = cloudflare_connectivity_directory_service.quizmon_database.service_id
    scheme     = "postgresql"
    database   = "quizmon"
    user       = "quizmon"
    password   = random_password.quizmon_database["quizmon"].result
  }
  caching = {
    disabled = true
  }
  origin_connection_limit = 10
  lifecycle {
    prevent_destroy = true
  }
}

data "cloudflare_account_api_token_permission_groups_list" "quizmon" {
  provider   = cloudflare.account
  account_id = local.cloudflare_account_id
}

resource "cloudflare_account_token" "quizmon_dns" {
  provider   = cloudflare.account
  account_id = local.cloudflare_account_id
  name       = "quizmon-cert-manager"
  policies = [{
    effect = "allow"
    permission_groups = [for name in ["DNS Write", "Zone Read"] : {
      id = one([for permission in data.cloudflare_account_api_token_permission_groups_list.quizmon.result :
        permission.id if permission.name == name && contains(permission.scopes, "com.cloudflare.api.account.zone")
      ])
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${local.cloudflare_zone_id}" = "*"
    })
  }]
}

resource "cloudflare_account_token" "quizmon_release" {
  provider   = cloudflare.account
  account_id = local.cloudflare_account_id
  name       = "quizmon-release"
  policies = [{
    effect = "allow"
    permission_groups = [for name in ["Workers Scripts Write", "Hyperdrive Read"] : {
      id = one([for permission in data.cloudflare_account_api_token_permission_groups_list.quizmon.result :
        permission.id if permission.name == name && contains(permission.scopes, "com.cloudflare.api.account")
      ])
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.${local.cloudflare_account_id}" = "*"
    })
  }]
}

output "quizmon_inputs" {
  sensitive = true
  value = {
    database_host = local.quizmon_database_host
    database_passwords = {
      for name, password in random_password.quizmon_database : name => password.result
    }
    auth_secret   = random_password.quizmon_auth.result
    dns_token     = cloudflare_account_token.quizmon_dns.value
    cloudflare    = { accountId = local.cloudflare_account_id, token = cloudflare_account_token.quizmon_release.value }
    hyperdrive_id = try(cloudflare_hyperdrive_config.quizmon[0].id, null)
  }
}
