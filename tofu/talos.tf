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
  talos_image_raw_url = "https://factory.talos.dev/image/${talos_image_factory_schematic.frodo.id}/${local.talos_version}/hcloud-arm64.raw.xz"
}

resource "imager_image" "frodo" {
  architecture = "arm"
  image_url    = local.talos_image_raw_url
  location     = local.hcloud_location
  description  = "Talos ${local.talos_version} (frodo schematic)"
  labels = {
    os        = "talos"
    schematic = talos_image_factory_schematic.frodo.id
  }
}
