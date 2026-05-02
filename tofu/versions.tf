terraform {
  required_version = "1.15.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "= 1.60.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 4.52.7"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "= 0.10.1"
    }

    imager = {
      source  = "hcloud-talos/imager"
      version = "= 1.0.5"
    }

    random = {
      source  = "hashicorp/random"
      version = "= 3.8.1"
    }

    minio = {
      source  = "aminueza/minio"
      version = "= 3.30.0"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "= 0.28.0"
    }
  }
}
