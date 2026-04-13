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
