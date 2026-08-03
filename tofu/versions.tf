terraform {
  required_version = "1.15.8"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.68.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.8"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }

    imager = {
      source  = "hcloud-talos/imager"
      version = "1.0.18"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }

    minio = {
      source  = "aminueza/minio"
      version = "3.38.5"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "6.57.1"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "= 0.28.0"
    }

    sentry = {
      source  = "jianyuan/sentry"
      version = "= 0.15.4"
    }
  }
}
