data "talos_image_factory_extensions_versions" "this" {
  talos_version = local.talos_version
  filters = {
    names = ["hcloud", "qemu-guest-agent", "tailscale"]
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
  architecture = "arm"
  image_url    = "https://factory.talos.dev/image/${talos_image_factory_schematic.shire.id}/${local.talos_version}/hcloud-arm64.raw.xz"
  location     = local.hcloud_location
  description  = "Talos ${local.talos_version} (shire schematic)"
}
