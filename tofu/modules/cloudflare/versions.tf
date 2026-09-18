terraform {
  required_providers {
    cloudflare = {
      source                = "cloudflare/cloudflare"
      configuration_aliases = [cloudflare.account, cloudflare.web_analytics]
    }

    random = {
      source = "hashicorp/random"
    }
  }
}
