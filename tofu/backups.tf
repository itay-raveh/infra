variable "backup_s3_principals" {
  description = "Dedicated Hetzner S3 credentials for each backup consumer, created outside the bucket's project."
  type = map(object({
    project_id    = string
    access_key_id = string
  }))
  sensitive = true

  validation {
    condition = (
      toset(keys(var.backup_s3_principals)) == toset(["etcd", "wanderbound", "quizmon"]) &&
      length(distinct([for principal in values(var.backup_s3_principals) : principal.access_key_id])) == 3 &&
      alltrue([for principal in values(var.backup_s3_principals) :
        can(regex("^[0-9]+$", principal.project_id)) &&
        can(regex("^[A-Z0-9]{20}$", principal.access_key_id)) &&
        principal.access_key_id != var.s3_access_key_id
      ])
    )
    error_message = "Provide distinct etcd, Wanderbound and Quizmon backup keys, separate from the provisioning key."
  }
}

resource "minio_s3_bucket" "backups" {
  bucket = "shire-backups"
}

locals {
  backup_prefixes = {
    etcd        = ["etcd/"]
    wanderbound = ["cnpg/wanderbound/", "app-data/wanderbound/"]
    quizmon     = ["cnpg/quizmon/"]
  }
}

resource "minio_s3_bucket_policy" "backups" {
  bucket = minio_s3_bucket.backups.bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      for consumer, prefixes in local.backup_prefixes : {
        Sid    = "${consumer}Objects"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam:::user/p${var.backup_s3_principals[consumer].project_id}:${var.backup_s3_principals[consumer].access_key_id}"
        }
        Action = concat([
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:PutObject",
          ], consumer == "etcd" ? [] : [
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
        ])
        Resource = [for prefix in prefixes : "${minio_s3_bucket.backups.arn}/${prefix}*"]
      }
      ], [{
        Sid    = "DatabaseBucketChecks"
        Effect = "Allow"
        Principal = {
          AWS = [for consumer in ["wanderbound", "quizmon"] :
            "arn:aws:iam:::user/p${var.backup_s3_principals[consumer].project_id}:${var.backup_s3_principals[consumer].access_key_id}"
          ]
        }
        # HeadBucket requires ListBucket without an s3:prefix condition.
        # https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadBucket.html
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [minio_s3_bucket.backups.arn]
    }])
  })
}

resource "minio_s3_bucket_versioning" "backups" {
  bucket = minio_s3_bucket.backups.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

resource "minio_ilm_policy" "backups" {
  bucket = minio_s3_bucket.backups.bucket

  rule {
    id     = "cnpg-expire"
    filter = "cnpg/"

    # Barman retains the base backup preceding the 30-day recovery window.
    # https://cloudnative-pg.io/plugin-barman-cloud/docs/retention/
    noncurrent_expiration {
      days = "60d"
    }
  }

  rule {
    id     = "etcd-expire"
    filter = "etcd/"

    expiration = "7d"

    noncurrent_expiration {
      days = "14d"
    }
  }

  depends_on = [minio_s3_bucket_versioning.backups]
}
