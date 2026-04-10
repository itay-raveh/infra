variable "encryption_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for client-side state encryption. Injected as TF_VAR_encryption_passphrase by the mise tofu-apply task, which sops-decrypts tofu/encryption-passphrase.sops.txt."
}

variable "hcloud_token" {
  type        = string
  sensitive   = true
  description = "Hetzner Cloud API token (Read & Write)."
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token scoped to Zone:DNS edit + Zero Trust edit on raveh.dev."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID for raveh.dev."
}

variable "ssh_public_key_path" {
  type        = string
  description = "Filesystem path to the SSH public key used only for Hetzner rescue-mode break-glass (Talos itself does not use SSH)."
}
