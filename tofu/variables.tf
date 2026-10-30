variable "encryption_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for client-side state encryption."
}

variable "hcloud_token" {
  type        = string
  sensitive   = true
  description = "Hetzner Cloud API token - Read & Write."
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare zone and services token. Permissions are listed in docs/cloudflare.md."
}

variable "ssh_public_key_path" {
  type        = string
  description = "SSH public key for Hetzner rescue access."
}

variable "wireguard_server_private_key" {
  type        = string
  sensitive   = true
  description = "WireGuard private key for the Talos management interface."
}

variable "wireguard_workstation_public_key" {
  type        = string
  sensitive   = true
  description = "WireGuard public key for the trusted workstation peer."
}

variable "s3_access_key_id" {
  type        = string
  sensitive   = true
  description = "Hetzner Object Storage access key."
}

variable "s3_secret_access_key" {
  type        = string
  sensitive   = true
  description = "Hetzner Object Storage secret key."
}

variable "cloudflare_web_analytics_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare account administration and Web Analytics token."
}

variable "cloudflare_primary_email" {
  type        = string
  sensitive   = true
  description = "Cloudflare login address for daily administration."
}

variable "cloudflare_gmail_email" {
  type        = string
  sensitive   = true
  description = "Gmail login address for Cloudflare recovery."
}

variable "cloudflare_proton_email" {
  type        = string
  sensitive   = true
  description = "Native Proton login address for Cloudflare recovery."
}
