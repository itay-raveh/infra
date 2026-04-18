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

  # x86-only (CX33); skip downloading the ARM schematic.
  talos_image_id_x86 = imager_image.shire.id
  disable_arm        = true

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

  talos_control_plane_extra_config_patches = [
    yamlencode({
      machine = {
        install = {
          # Platform-specific installer pins the hcloud UKI; the generic
          # installer/ variant picks the currently running platform, which
          # once metal is active traps us in metal forever.
          image             = "factory.talos.dev/hcloud-installer/${talos_image_factory_schematic.shire.id}:${local.talos_version}"
          extraKernelArgs   = ["talos.platform=hcloud"]
          grubUseUKICmdline = false
        }
        kubelet = {
          extraMounts = [{
            destination = "/var/local-path-provisioner"
            type        = "bind"
            source      = "/var/local-path-provisioner"
            options     = ["bind", "rshared", "rw"]
          }]
        }
        features = {
          kubernetesTalosAPIAccess = {
            enabled                     = true
            allowedRoles                = ["os:etcd:backup"]
            allowedKubernetesNamespaces = ["kube-system"]
          }
        }
      }
    }),
    # Hetzner platform metadata hostname doesn't survive talosctl upgrade
    # on UKI installs (siderolabs/talos#11145), so pin it here.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      auto       = "off"
      hostname   = "shire-control-plane-1"
    }),
  ]
}
