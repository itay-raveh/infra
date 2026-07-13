module "talos" {
  source  = "hcloud-talos/talos/hcloud"
  version = "3.4.1"

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

  bootstrap_endpoint_mode    = "private_ip"
  kubeconfig_endpoint_mode   = "private_ip"
  talosconfig_endpoints_mode = "private_ip"
  enable_alias_ip            = false

  hcloud_ccm_version = "1.30.1"
  cilium_values      = [file("${path.module}/cilium-values.yaml")]

  firewall_use_current_ip = false
  extra_firewall_rules = [{
    direction   = "in"
    protocol    = "udp"
    port        = "51820"
    source_ips  = ["0.0.0.0/0"]
    description = "WireGuard management tunnel"
  }]

  talos_control_plane_extra_config_patches = [
    yamlencode({
      machine = {
        install = {
          # The platform-specific installer pins the hcloud UKI. The generic
          # installer variant picks the currently running platform, which
          # once metal is active traps us in metal forever.
          image             = "factory.talos.dev/hcloud-installer/${talos_image_factory_schematic.shire.id}:${local.talos_version}"
          extraKernelArgs   = ["talos.platform=hcloud", "net.ifnames=0"]
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
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "WireguardConfig"
      name       = "wg0"
      privateKey = var.wireguard_server_private_key
      listenPort = 51820
      addresses = [{
        address = "10.200.0.1/24"
      }]
      peers = [{
        publicKey  = var.wireguard_workstation_public_key
        allowedIPs = ["10.200.0.250/32"]
      }]
    }),
  ]
}
