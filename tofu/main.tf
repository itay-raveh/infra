data "sops_file" "tailscale_auth_key" {
  source_file = "${path.root}/../talos/tailscale-authkey.sops.txt"
  input_type  = "raw"
}

module "talos" {
  source  = "hcloud-talos/talos/hcloud"
  version = "= 3.2.3"

  cluster_name       = local.cluster_name
  cluster_prefix     = true
  location_name      = local.hcloud_location
  hcloud_token       = var.hcloud_token
  talos_version      = local.talos_version
  kubernetes_version = local.kubernetes_version
  ssh_public_key     = file(var.ssh_public_key_path)

  # ARM-only (CAX21); skip downloading the x86 schematic.
  talos_image_id_arm = imager_image.shire.id
  disable_x86        = true

  control_plane_nodes = [
    { id = 1, type = local.hcloud_server_type },
  ]
  worker_nodes = []

  # Single-node cluster: workloads run on the control plane.
  control_plane_allow_schedule = true

  # Talos + k8s APIs closed to the public internet; we reach them via Tailscale.
  firewall_use_current_ip = false

  tailscale = {
    enabled  = true
    auth_key = data.sops_file.tailscale_auth_key.raw
  }

  talos_control_plane_extra_config_patches = [local.patch_data_volume_mount]
}

locals {
  # Talos kubelet runs in its own container, so the host bind-mount at
  # /var/mnt/data is invisible to pods unless extraMounts re-binds it with
  # rshared propagation.
  patch_data_volume_mount = yamlencode({
    machine = {
      disks = [{
        device = "/dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.data.id}"
        partitions = [{
          mountpoint = "/var/mnt/data"
        }]
      }]
      kubelet = {
        extraMounts = [{
          destination = "/var/mnt/data"
          type        = "bind"
          source      = "/var/mnt/data"
          options     = ["bind", "rshared", "rw"]
        }]
      }
    }
  })
}

resource "hcloud_volume" "data" {
  name     = "${local.cluster_name}-data"
  size     = 40
  location = local.hcloud_location
  format   = "ext4"

  lifecycle {
    prevent_destroy = true
  }
}

data "hcloud_server" "cp1" {
  name       = "${local.cluster_name}-control-plane-1"
  depends_on = [module.talos]
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = data.hcloud_server.cp1.id
  automount = false
}
