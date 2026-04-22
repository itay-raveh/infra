provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "imager" {
  token = var.hcloud_token
}

provider "minio" {
  minio_server   = "fsn1.your-objectstorage.com"
  minio_user     = var.s3_access_key_id
  minio_password = var.s3_secret_access_key
  minio_ssl      = true
  minio_region   = "fsn1"
  s3_compat_mode = true
}

# Auth via TAILSCALE_OAUTH_CLIENT_ID/SECRET env vars (tofu/secrets.sops.yaml, unwrapped by tofu-wrapper.sh).
provider "tailscale" {
  tailnet = "-"
  scopes = [
    "policy_file",      # tailscale_acl
    "oauth_keys",       # tailscale_oauth_client
    "feature_settings", # tailscale_tailnet_settings
    "dns",              # tailscale_dns_preferences
  ]
}
