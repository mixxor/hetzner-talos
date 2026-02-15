resource "terraform_data" "cilium" {
  triggers_replace = [
    var.cilium_version,
    filesha256("${path.module}/files/cilium-values.yaml"),
  ]

  depends_on = [
    terraform_data.cluster_ready,
    talos_machine_configuration_apply.worker,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      source ${path.module}/files/kubeconfig-env.sh
      helm upgrade --install cilium cilium \
        --repo https://helm.cilium.io \
        --version "$CILIUM_VERSION" \
        --namespace kube-system \
        --values ${path.module}/files/cilium-values.yaml \
        --wait --timeout 10m
    EOT
    environment = {
      KUBECONFIG_B64 = local.deploy_kubeconfig_b64
      CILIUM_VERSION = var.cilium_version
    }
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "echo 'Cilium: managed by cluster, not removed on destroy'"
  }
}
