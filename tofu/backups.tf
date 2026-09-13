resource "minio_s3_bucket" "backups" {
  bucket = "shire-backups"
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
