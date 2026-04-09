# OpenTofu state is stored in Hetzner Object Storage (S3-compatible).
# The bucket must be created manually before `tofu init` — see docs/setup.md.

terraform {
  backend "s3" {
    bucket = "raveh-infra-tfstate"
    key    = "frodo/terraform.tfstate"
    region = "eu-central-1" # Hetzner Object Storage region

    # Hetzner S3-compatible endpoint.
    # Credentials come from environment: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.
    endpoints = {
      s3 = "https://fsn1.your-objectstorage.com"
    }

    # Hetzner Object Storage does not support these features.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
