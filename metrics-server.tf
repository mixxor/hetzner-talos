# Cluster readiness gate -- all helm resources depend on this instead of
# duplicating API-server retry loops.
resource "terraform_data" "cluster_ready" {
  depends_on = [
    talos_machine_bootstrap.this,
    talos_cluster_kubeconfig.this,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      source ${path.module}/files/kubeconfig-env.sh
      for i in $(seq 1 60); do
        kubectl get ns kube-system >/dev/null 2>&1 && echo "API server ready" && exit 0
        echo "Waiting for API server... ($i/60)"
        sleep 5
      done
      echo "ERROR: API server not ready after 5 minutes" >&2
      exit 1
    EOT
    environment = {
      KUBECONFIG_B64 = local.deploy_kubeconfig_b64
    }
  }
}

resource "terraform_data" "metrics_server" {
  triggers_replace = [var.metrics_server_version]

  depends_on = [terraform_data.cilium]

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      source ${path.module}/files/kubeconfig-env.sh
      helm upgrade --install metrics-server metrics-server \
        --repo https://kubernetes-sigs.github.io/metrics-server/ \
        --version "$VERSION" \
        --namespace kube-system \
        --set args={--kubelet-insecure-tls} \
        --wait --timeout 5m
    EOT
    environment = {
      KUBECONFIG_B64 = local.deploy_kubeconfig_b64
      VERSION        = var.metrics_server_version
    }
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "echo 'Skipping metrics-server uninstall'"
  }
}
