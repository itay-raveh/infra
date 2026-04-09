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

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to install on the server"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
