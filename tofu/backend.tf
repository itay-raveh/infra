terraform {
  # S3 backend on Hetzner Object Storage (Ceph-compatible, path-style)
  backend "s3" {
    bucket = "shire-tfstate"
    key    = "shire/terraform.tfstate"

    endpoints = {
      s3 = "https://fsn1.your-objectstorage.com"
    }

    region = "fsn1"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }

  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.encryption_passphrase
    }

    method "aes_gcm" "primary" {
      keys = key_provider.pbkdf2.passphrase
    }

    state {
      method   = method.aes_gcm.primary
      enforced = true
    }

    plan {
      method   = method.aes_gcm.primary
      enforced = true
    }
  }
}
