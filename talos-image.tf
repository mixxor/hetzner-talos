# Talos snapshot: created automatically on first apply, skipped if it already exists.

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.talos_extensions
      }
    }
  })
}

locals {
  talos_schematic_id = talos_image_factory_schematic.this.id
  talos_image_id     = "factory.talos.dev/installer/${local.talos_schematic_id}:${var.talos_version}"
  talos_image_url    = "https://factory.talos.dev/image/${local.talos_schematic_id}/${var.talos_version}/hcloud-amd64.raw.xz"
}

resource "terraform_data" "talos_snapshot" {
  triggers_replace = [var.talos_version, local.talos_schematic_id]

  provisioner "local-exec" {
    command = "${path.module}/files/build-talos-snapshot.sh"
    environment = {
      HCLOUD_TOKEN  = var.hcloud_token
      TALOS_VERSION = var.talos_version
      IMAGE_URL     = local.talos_image_url
      LOCATION      = var.location
    }
  }
}

data "hcloud_images" "talos" {
  with_selector = "talos-version=${var.talos_version}"
  depends_on    = [terraform_data.talos_snapshot]
}

locals {
  talos_snapshot_id = try(data.hcloud_images.talos.images[0].id, null)
}
