terraform {
  required_version = "1.16.1"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.68.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.24.0"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }

    imager = {
      source  = "hcloud-talos/imager"
      version = "1.0.19"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }

    minio = {
      source  = "aminueza/minio"
      version = "3.41.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "6.62.0"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }

    sentry = {
      source  = "jianyuan/sentry"
      version = "0.15.6"
    }
  }
}
