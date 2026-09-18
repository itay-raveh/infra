mock_provider "hcloud" {}
mock_provider "talos" {}
mock_provider "imager" {}
mock_provider "random" {}
mock_provider "minio" {}
mock_provider "aws" {}
mock_provider "aws" {
  alias = "hetzner_object_storage"
}
mock_provider "tailscale" {}
mock_provider "sentry" {}
mock_provider "cloudflare" {}
mock_provider "cloudflare" {
  alias = "web_analytics"
}
mock_provider "cloudflare" {
  alias = "account"
}

variables {
  encryption_passphrase                       = "fixture"
  hcloud_token                                = "fixture"
  cloudflare_api_token                        = "fixture"
  cloudflare_web_analytics_api_token          = "fixture"
  ssh_public_key_path                         = "unused-in-backup-plan"
  wireguard_server_private_key                = "fixture"
  wireguard_workstation_public_key            = "fixture"
  s3_access_key_id                            = "fixture"
  s3_secret_access_key                        = "fixture"
  wanderbound_upload_s3_credential_project_id = "fixture"
  wanderbound_upload_s3_access_key_id         = "fixture"
  cloudflare_primary_email                    = "primary@example.invalid"
  cloudflare_gmail_email                      = "recovery-a@example.invalid"
  cloudflare_proton_email                     = "recovery-b@example.invalid"
}

run "preserve_database_recovery_window" {
  command = plan
  # Root imports are unsupported by OpenTofu's mocked providers.
  plan_options {
    target = [minio_ilm_policy.backups]
  }
  assert {
    condition     = one(minio_s3_bucket_versioning.backups.versioning_configuration).status == "Enabled"
    error_message = "Backup storage must retain replaced objects."
  }
  assert {
    condition = alltrue([
      for rule in minio_ilm_policy.backups.rule :
      rule.expiration == null && alltrue([
        for expiry in rule.noncurrent_expiration :
        tonumber(trimsuffix(expiry.days, "d")) >= tonumber(trimsuffix(yamldecode(file("../clusters/shire/apps/wanderbound/objectstore.yaml")).spec.retentionPolicy, "d"))
      ]) if rule.filter == "cnpg/"
    ]) && length([for rule in minio_ilm_policy.backups.rule : rule if rule.filter == "cnpg/"]) == 1
    error_message = "S3 must not expire current CNPG objects independently of Barman, or remove old versions before its recovery window."
  }
}
