terraform {
  # S3 backend on Hetzner Object Storage (Ceph-compatible, path-style)
  backend "s3" {
    bucket = "raveh-infra-tfstate"
    key    = "frodo/terraform.tfstate"

    endpoints = {
      s3 = "https://hel1.your-objectstorage.com"
    }

    region = "hel1"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }

  # Client-side AES-GCM encryption; passphrase injected at apply-time via mise task
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
