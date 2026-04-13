locals {
  cluster_name       = "shire"
  hcloud_location    = "hel1"
  hcloud_server_type = "cx33"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.2"

  cloudflare_zone_id    = "4be281e220538b2ad2def80f8f5150a5"
  cloudflare_account_id = "d695541408d207c8e7750de4fddf5bf5"
}
