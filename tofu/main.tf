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

  # Open 50000 (Talos API) and 6443 (k8s API) to all sources. Both
  # ports are mTLS-protected so this is safe. firewall_use_current_ip
  # doesn't work reliably here because the ISP may NAT traffic to
  # Hetzner through a different egress IP than what icanhazip reports.
  # Day-2 access goes through Tailscale anyway.
  firewall_use_current_ip   = false
  firewall_talos_api_source = ["0.0.0.0/0"]
  firewall_kube_api_source  = ["0.0.0.0/0"]

  tailscale = {
    enabled  = true
    auth_key = var.tailscale_auth_key
  }

  talos_control_plane_extra_config_patches = []
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

# The disk config patch can't be in the initial machine config because the
# volume isn't attached until after bootstrap completes (module.talos creates
# the server + bootstraps as one unit, and the attachment depends on the
# module finishing). Apply the disk config separately once the volume is
# attached so Talos can actually find the device.
resource "talos_machine_configuration_apply" "data_volume" {
  client_configuration        = module.talos.talos_client_configuration.client_configuration
  machine_configuration_input = module.talos.talos_machine_configurations_control_plane["shire-control-plane-1"].machine_configuration
  node                        = module.talos.public_ipv4_list[0]
  config_patches              = [local.patch_data_volume_mount]

  depends_on = [hcloud_volume_attachment.data]
}
