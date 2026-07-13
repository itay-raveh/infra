variable "encryption_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for client-side state encryption (from tofu/secrets.sops.yaml)."
}

variable "hcloud_token" {
  type        = string
  sensitive   = true
  description = "Hetzner Cloud API token - Read & Write (from tofu/secrets.sops.yaml)."
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token - Zone:DNS edit + Zero Trust edit on raveh.dev (from tofu/secrets.sops.yaml)."
}

variable "ssh_public_key_path" {
  type        = string
  description = "Filesystem path to the primary YubiKey FIDO2-sk pubkey (from mise.toml [env]). Used only for Hetzner rescue-mode break-glass; Talos itself does not use SSH."
}

variable "wireguard_server_private_key" {
  type        = string
  sensitive   = true
  description = "WireGuard private key for the Talos management interface (from tofu/secrets.sops.yaml)."
}

variable "wireguard_workstation_public_key" {
  type        = string
  sensitive   = true
  description = "WireGuard public key for the trusted workstation peer (from tofu/secrets.sops.yaml)."
}

variable "s3_access_key_id" {
  type        = string
  sensitive   = true
  description = "Hetzner Object Storage access key (from tofu/secrets.sops.yaml)."
}

variable "s3_secret_access_key" {
  type        = string
  sensitive   = true
  description = "Hetzner Object Storage secret key (from tofu/secrets.sops.yaml)."
}

variable "wanderbound_upload_s3_credential_project_id" {
  type        = string
  sensitive   = true
  description = "Hetzner project ID for the dedicated Wanderbound upload credential (from tofu/secrets.sops.yaml)."
}

variable "wanderbound_upload_s3_access_key_id" {
  type        = string
  sensitive   = true
  description = "Hetzner Object Storage access key for the dedicated Wanderbound upload credential (from tofu/secrets.sops.yaml)."
}
