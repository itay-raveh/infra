terraform {
  required_version = "1.12.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.69.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.25.0"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }

    imager = {
      source  = "hcloud-talos/imager"
      version = "1.0.23"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }

    minio = {
      source  = "aminueza/minio"
      version = "3.43.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }

    sentry = {
      source  = "jianyuan/sentry"
      version = "0.15.7"
    }
  }
}
