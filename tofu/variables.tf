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
  description = "Cloudflare API token - DNS, Single Redirect, and Workers Routes edit on the zone, plus Workers Scripts and Zero Trust edit on its account."
}

variable "ssh_public_key_path" {
  type        = string
  description = "Filesystem path to the primary YubiKey FIDO2-sk pubkey (from mise.toml [env]). Used only for Hetzner rescue-mode break-glass; Talos itself does not use SSH."
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

variable "wanderbound_upload_s3_credential_project_id" {
  type        = string
  sensitive   = true
  description = "Hetzner project ID for the dedicated Wanderbound upload credential."
}

variable "wanderbound_upload_s3_access_key_id" {
  type        = string
  sensitive   = true
  description = "Hetzner Object Storage access key for the dedicated Wanderbound upload credential."
}

variable "cloudflare_web_analytics_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token with Account Settings read and write access for Web Analytics."
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
