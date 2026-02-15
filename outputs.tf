output "kubeconfig" {
  description = "Kubeconfig for kubectl access (uses private LB IP)"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "kubeconfig_public" {
  description = "Kubeconfig using public CP IP (direct access)"
  value = replace(
    talos_cluster_kubeconfig.this.kubeconfig_raw,
    "https://${hcloud_load_balancer_network.k8s_api.ip}:6443",
    "https://${hcloud_server.control_plane[0].ipv4_address}:6443"
  )
  sensitive = true
}

output "talosconfig" {
  description = "Talosconfig for talosctl access"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "control_plane_ips" {
  description = "Public IPs of control plane nodes"
  value       = [for s in hcloud_server.control_plane : s.ipv4_address]
}

output "control_plane_private_ips" {
  description = "Private IPs of control plane nodes"
  value       = [for n in hcloud_server_network.control_plane : n.ip]
}

output "worker_ips" {
  description = "Public IPs of worker nodes (keyed by pool-index)"
  value       = { for k, s in hcloud_server.worker : k => s.ipv4_address }
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes (keyed by pool-index)"
  value       = { for k, n in hcloud_server_network.worker : k => n.ip }
}

output "k8s_api_lb_ip" {
  description = "Private IP of the Kubernetes API load balancer"
  value       = hcloud_load_balancer_network.k8s_api.ip
}

output "talos_snapshot_id" {
  description = "Hetzner Cloud snapshot ID for Talos"
  value       = local.talos_snapshot_id
}

output "firewall_allowed_cidrs" {
  description = "CIDR ranges allowed in firewall for K8s/Talos API access"
  value       = local.firewall_external_cidrs
}

output "network_id" {
  description = "Hetzner network ID used by the cluster"
  value       = local.network_id
}

output "network_name" {
  description = "Hetzner network name used by the cluster"
  value       = local.network_name
}

output "cluster_ready" {
  description = "Readiness marker — all core components (Cilium, CCM, CSI, metrics-server) are deployed. Use depends_on with this output."
  value       = true

  depends_on = [
    terraform_data.cilium,
    terraform_data.hcloud_csi,
    terraform_data.metrics_server,
  ]
}

output "connection_info" {
  description = "Connection information for the cluster"
  value = join("\n", [
    "  tofu output -raw kubeconfig_public > ~/.kube/hetzner",
    "  export KUBECONFIG=~/.kube/hetzner",
    "",
    "API: https://${hcloud_server.control_plane[0].ipv4_address}:6443",
  ])
}

output "cluster_summary" {
  description = "Summary of deployed resources"
  value = {
    cluster_name = var.cluster_name
    versions = {
      talos      = var.talos_version
      kubernetes = var.kubernetes_version
      cilium     = var.cilium_version
      hcloud_ccm = var.hcloud_ccm_version
      hcloud_csi = var.enable_csi ? var.hcloud_csi_version : null
    }
    control_plane = {
      count       = var.control_plane_count
      type        = var.control_plane_server_type
      public_ips  = [for s in hcloud_server.control_plane : s.ipv4_address]
      private_ips = [for n in hcloud_server_network.control_plane : n.ip]
    }
    worker_pools = [for pool in var.worker_nodepools : {
      name        = pool.name
      count       = pool.count
      server_type = pool.server_type
      locations   = pool.locations
    }]
    workers = {
      total_count = sum([for pool in var.worker_nodepools : pool.count])
      public_ips  = { for k, s in hcloud_server.worker : k => s.ipv4_address }
      private_ips = { for k, n in hcloud_server_network.worker : k => n.ip }
    }
    load_balancers = {
      k8s_api_private_ip = hcloud_load_balancer_network.k8s_api.ip
    }
    total_servers = var.control_plane_count + sum([for pool in var.worker_nodepools : pool.count])
  }
}

