data "talos_image_factory_extensions_versions" "this" {
  talos_version = local.talos_version
  filters = {
    names = ["hcloud", "qemu-guest-agent", "tailscale"]
  }
}

resource "talos_image_factory_schematic" "frodo" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
    }
  })
}

locals {
  talos_installer_image = "factory.talos.dev/installer/${talos_image_factory_schematic.frodo.id}:${local.talos_version}"
}
