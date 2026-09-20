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
  backup_s3_principals = {
    etcd        = { project_id = "12345678", access_key_id = "AAAAAAAAAAAAAAAAAAAA" }
    wanderbound = { project_id = "12345678", access_key_id = "BBBBBBBBBBBBBBBBBBBB" }
    quizmon     = { project_id = "12345678", access_key_id = "CCCCCCCCCCCCCCCCCCCC" }
  }
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
        tonumber(trimsuffix(expiry.days, "d")) >= max(flatten([
          for path in fileset("../clusters/shire/apps", "**/*.yaml") : [
            for document in split("\n---", file("../clusters/shire/apps/${path}")) :
            tonumber(trimsuffix(yamldecode(document).spec.retentionPolicy, "d"))
            if try(yamldecode(document).kind == "ObjectStore", false)
          ]
        ])...)
      ]) if rule.filter == "cnpg/"
    ]) && length([for rule in minio_ilm_policy.backups.rule : rule if rule.filter == "cnpg/"]) == 1
    error_message = "S3 must not expire current CNPG objects independently of Barman, or remove old versions before its recovery window."
  }
}

run "isolate_backup_credentials" {
  command = plan
  plan_options {
    target = [minio_s3_bucket_policy.backups]
  }
  override_resource {
    target = minio_s3_bucket.backups
    values = { arn = "arn:aws:s3:::shire-backups" }
  }
  assert {
    condition = alltrue([
      for statement in jsondecode(minio_s3_bucket_policy.backups.policy).Statement :
      alltrue([
        for resource in statement.Resource :
        startswith(resource, "arn:aws:s3:::shire-backups")
        ]) && alltrue([
        for action in statement.Action : contains([
          "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts", "s3:PutObject",
          "s3:DeleteObject", "s3:GetObject", "s3:GetObjectVersion",
          "s3:GetBucketLocation", "s3:ListBucket",
        ], action)
      ]) if statement.Effect == "Allow"
    ]) && length(jsondecode(minio_s3_bucket_policy.backups.policy).Statement) == 10
    error_message = "Backup keys must not receive state access, bucket administration or permanent version deletion."
  }
  assert {
    condition = alltrue([
      for statement in jsondecode(minio_s3_bucket_policy.backups.policy).Statement :
      statement.Sid == "DatabaseBucketChecks" ? (
        toset(statement.Action) == toset(["s3:GetBucketLocation", "s3:ListBucket"]) &&
        toset(statement.Resource) == toset(["arn:aws:s3:::shire-backups"]) &&
        toset(statement.Principal.AWS) == toset([
          "arn:aws:iam:::user/p12345678:BBBBBBBBBBBBBBBBBBBB",
          "arn:aws:iam:::user/p12345678:CCCCCCCCCCCCCCCCCCCC",
        ]) && !can(statement.Condition)
        ) : (
        toset(statement.Resource) == {
          etcdObjects        = toset(["arn:aws:s3:::shire-backups/etcd/*"])
          wanderboundObjects = toset(["arn:aws:s3:::shire-backups/cnpg/wanderbound/*", "arn:aws:s3:::shire-backups/app-data/wanderbound/*"])
          quizmonObjects     = toset(["arn:aws:s3:::shire-backups/cnpg/quizmon/*"])
        }[statement.Sid] &&
        statement.Principal.AWS == {
          etcdObjects        = "arn:aws:iam:::user/p12345678:AAAAAAAAAAAAAAAAAAAA"
          wanderboundObjects = "arn:aws:iam:::user/p12345678:BBBBBBBBBBBBBBBBBBBB"
          quizmonObjects     = "arn:aws:iam:::user/p12345678:CCCCCCCCCCCCCCCCCCCC"
        }[statement.Sid] &&
        contains(statement.Action, "s3:PutObject") &&
        contains(statement.Action, "s3:GetObject") == (statement.Sid != "etcdObjects") &&
        contains(statement.Action, "s3:DeleteObject") == (statement.Sid != "etcdObjects") &&
        !contains(statement.Action, "s3:ListBucket")
      ) if statement.Effect == "Allow"
    ])
    error_message = "Each backup key must be restricted to its own object paths, with etcd write-only and Barman bucket checks allowed."
  }
  assert {
    condition = alltrue([
      for consumer in ["etcd", "wanderbound", "quizmon"] : alltrue([
        for statement in jsondecode(minio_s3_bucket_policy.backups.policy).Statement :
        statement.Effect == "Deny" && statement.Principal == one([
          for grant in jsondecode(minio_s3_bucket_policy.backups.policy).Statement : grant.Principal
          if grant.Sid == "${consumer}Objects"
          ]) && (statement.Sid == "${consumer}OtherPaths" ? (
          toset(statement.Action) == toset(["s3:*"]) &&
          toset(statement.NotResource) == toset(concat(one([
            for grant in jsondecode(minio_s3_bucket_policy.backups.policy).Statement : grant.Resource
            if grant.Sid == "${consumer}Objects"
          ]), consumer == "etcd" ? [] : ["arn:aws:s3:::shire-backups"]))
          ) : (
          toset(statement.Resource) == toset(["arn:aws:s3:::shire-backups", "arn:aws:s3:::shire-backups/*"]) &&
          toset(statement.NotAction) == toset(concat(one([
            for grant in jsondecode(minio_s3_bucket_policy.backups.policy).Statement : grant.Action
            if grant.Sid == "${consumer}Objects"
          ]), consumer == "etcd" ? [] : ["s3:GetBucketLocation", "s3:ListBucket"]))
        ))
        if contains(["${consumer}OtherPaths", "${consumer}OtherActions"], statement.Sid)
        ]) && length([
        for statement in jsondecode(minio_s3_bucket_policy.backups.policy).Statement : statement
        if contains(["${consumer}OtherPaths", "${consumer}OtherActions"], statement.Sid)
      ]) == 2
    ])
    error_message = "Explicit denies must prevent object ownership from bypassing each backup key's paths and actions."
  }
}

run "reject_provisioning_key_for_backups" {
  command = plan
  plan_options {
    target = [minio_s3_bucket_policy.backups]
  }
  variables {
    s3_access_key_id = "AAAAAAAAAAAAAAAAAAAA"
  }
  expect_failures = [var.backup_s3_principals]
}

run "reject_shared_runtime_backup_key" {
  command = plan
  plan_options {
    target = [minio_s3_bucket_policy.backups]
  }
  variables {
    backup_s3_principals = {
      etcd        = { project_id = "12345678", access_key_id = "AAAAAAAAAAAAAAAAAAAA" }
      wanderbound = { project_id = "12345678", access_key_id = "AAAAAAAAAAAAAAAAAAAA" }
      quizmon     = { project_id = "12345678", access_key_id = "CCCCCCCCCCCCCCCCCCCC" }
    }
  }
  expect_failures = [var.backup_s3_principals]
}
