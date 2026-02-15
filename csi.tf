resource "terraform_data" "hcloud_csi" {
  triggers_replace = [var.hcloud_csi_version]

  depends_on = [terraform_data.cluster_ready]

  lifecycle {
    enabled = var.enable_csi
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      source ${path.module}/files/kubeconfig-env.sh
      echo "$CSI_VALUES" | helm upgrade --install hcloud-csi hcloud-csi \
        --repo https://charts.hetzner.cloud \
        --version "$CSI_VERSION" \
        --namespace kube-system \
        --values - \
        --wait --timeout 10m
    EOT
    environment = {
      KUBECONFIG_B64 = local.deploy_kubeconfig_b64
      CSI_VERSION    = var.hcloud_csi_version
      CSI_VALUES = yamlencode({
        controller = {
          hcloudToken = {
            existingSecret = {
              name = "hcloud"
              key  = "token"
            }
          }
        }
        storageClasses = [{
          name                = "hcloud-volumes"
          defaultStorageClass = true
          reclaimPolicy       = "Delete"
        }]
      })
    }
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "echo 'Skipping CSI uninstall'"
  }
}
