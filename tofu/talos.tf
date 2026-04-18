data "talos_image_factory_extensions_versions" "this" {
  talos_version = local.talos_version
  filters = {
    names = ["iscsi-tools", "qemu-guest-agent", "tailscale", "util-linux-tools"]
  }
}

resource "talos_image_factory_schematic" "shire" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
    }
  })
}

resource "imager_image" "shire" {
  architecture = "x86"
  image_url    = "https://factory.talos.dev/image/${talos_image_factory_schematic.shire.id}/${local.talos_version}/hcloud-amd64.raw.xz"
  location     = local.hcloud_location
  description  = "Talos ${local.talos_version} (shire schematic)"
}
