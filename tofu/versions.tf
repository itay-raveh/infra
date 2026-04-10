terraform {
  required_version = "= 1.11.6"

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

    random = {
      source  = "hashicorp/random"
      version = "= 3.8.1"
    }

    sops = {
      source  = "carlpett/sops"
      version = "= 1.4.1"
    }
  }
}
