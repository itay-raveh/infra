mock_provider "cloudflare" {}
mock_provider "cloudflare" {
  alias = "account"
}
mock_provider "cloudflare" {
  alias = "web_analytics"
}
mock_provider "random" {}
mock_provider "hcloud" {}
mock_provider "talos" {}
mock_provider "imager" {}
mock_provider "minio" {}
mock_provider "aws" {}
mock_provider "tailscale" {}
mock_provider "sentry" {}

variables {
  backup_s3_operator_project_id = "87654321"
  backup_s3_principals = {
    etcd        = { project_id = "12345678", access_key_id = "AAAAAAAAAAAAAAAAAAAA" }
    wanderbound = { project_id = "12345678", access_key_id = "BBBBBBBBBBBBBBBBBBBB" }
    quizmon     = { project_id = "12345678", access_key_id = "CCCCCCCCCCCCCCCCCCCC" }
  }
  encryption_passphrase                       = "fixture"
  hcloud_token                                = "fixture"
  cloudflare_api_token                        = "fixture"
  ssh_public_key_path                         = "/dev/null"
  wireguard_server_private_key                = "fixture"
  wireguard_workstation_public_key            = "fixture"
  s3_access_key_id                            = "fixture"
  s3_secret_access_key                        = "fixture"
  wanderbound_upload_s3_credential_project_id = "fixture"
  wanderbound_upload_s3_access_key_id         = "fixture"
  cloudflare_web_analytics_api_token          = "fixture"
  cloudflare_primary_email                    = "primary@example.test"
  cloudflare_gmail_email                      = "secondary@example.test"
  cloudflare_proton_email                     = "recovery@example.test"
}

run "private_database" {
  command = plan
  plan_options {
    target = [cloudflare_connectivity_directory_service.quizmon_database, cloudflare_hyperdrive_config.quizmon]
  }
  assert {
    condition     = cloudflare_connectivity_directory_service.quizmon_database.tls_settings.cert_verification_mode == "verify_full"
    error_message = "The private database must verify the certificate chain and hostname."
  }
  assert {
    condition     = !cloudflare_dns_record.quizmon_database.proxied && cloudflare_dns_record.quizmon_database.content == "10.0.8.20"
    error_message = "Database DNS must point directly to the private CNPG Service."
  }
  assert {
    condition     = length(cloudflare_hyperdrive_config.quizmon) == 0
    error_message = "Database and certificate bootstrap must precede Hyperdrive creation."
  }
}

run "hyperdrive" {
  command = plan
  variables {
    quizmon_hyperdrive_enabled = true
  }
  plan_options {
    target = [cloudflare_hyperdrive_config.quizmon]
  }
  assert {
    condition     = cloudflare_hyperdrive_config.quizmon[0].caching.disabled
    error_message = "Account reads must not use the Hyperdrive result cache."
  }
  assert {
    condition     = cloudflare_hyperdrive_config.quizmon[0].origin_connection_limit == 10
    error_message = "Hyperdrive must leave connections available for sync and releases."
  }
  assert {
    condition     = cloudflare_hyperdrive_config.quizmon[0].origin.host == null && cloudflare_hyperdrive_config.quizmon[0].origin.access_client_id == null
    error_message = "The database connection must use the VPC service instead of a public origin or Access token."
  }
}
