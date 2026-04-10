variable "state_passphrase" {
  description = "Passphrase for client-side state and plan encryption (min 16 characters)"
  type        = string
  sensitive   = true
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token scoped to DNS editing for raveh.dev zone"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for raveh.dev"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (needed for Zero Trust resources)"
  type        = string
}

variable "admin_email" {
  description = "Email allowed through Cloudflare Access to reach the Komodo panel"
  type        = string
}

variable "komodo_bootstrap_password" {
  description = "First-boot admin password for Komodo. Only read by KOMODO_INIT_ADMIN_PASSWORD on initial container start — later changes do nothing; rotate via the Komodo UI."
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to install on the server"
  type        = string
}
