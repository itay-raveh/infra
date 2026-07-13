resource "minio_s3_bucket" "wanderbound_uploads" {
  bucket        = "wanderbound-uploads-raveh-dev"
  acl           = "private"
  force_destroy = false
}

resource "minio_s3_bucket_cors" "wanderbound_uploads" {
  bucket = minio_s3_bucket.wanderbound_uploads.bucket

  cors_rule {
    allowed_origins = ["https://wanderbound.raveh.dev"]
    allowed_methods = ["PUT"]
    allowed_headers = [
      "Authorization",
      "content-type",
      "x-amz-content-sha256",
      "x-amz-date",
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "wanderbound_uploads" {
  provider = aws.hetzner_object_storage
  bucket   = minio_s3_bucket.wanderbound_uploads.bucket

  lifecycle {
    ignore_changes = [transition_default_minimum_object_size]
  }

  rule {
    id     = "temporary-uploads"
    status = "Enabled"

    filter {
      prefix = "uploads/"
    }

    expiration {
      days = 3
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }
  }
}

resource "minio_s3_bucket_policy" "wanderbound_uploads" {
  bucket = minio_s3_bucket.wanderbound_uploads.bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam:::user/p${var.wanderbound_upload_s3_credential_project_id}:${var.wanderbound_upload_s3_access_key_id}"
      }
      Action = [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
      ]
      Resource = "${minio_s3_bucket.wanderbound_uploads.arn}/uploads/*"
    }]
  })
}
