resource "hcloud_placement_group" "control_plane" {
  name = "${var.cluster_name}-control-plane"
  type = "spread"

  labels = {
    role    = "control-plane"
    cluster = var.cluster_name
  }
}

resource "hcloud_server" "control_plane" {
  count              = var.control_plane_count
  name               = "${var.cluster_name}-cp-${count.index}"
  server_type        = var.control_plane_server_type
  image              = local.talos_snapshot_id
  location           = var.control_plane_locations[count.index % length(var.control_plane_locations)]
  placement_group_id = hcloud_placement_group.control_plane.id

  delete_protection  = var.delete_protection
  rebuild_protection = var.delete_protection

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  firewall_ids = [hcloud_firewall.cluster.id]

  labels = {
    role    = "control-plane"
    cluster = var.cluster_name
  }

  depends_on = [hcloud_network_subnet.control_plane]
}

resource "hcloud_server_network" "control_plane" {
  count      = var.control_plane_count
  server_id  = hcloud_server.control_plane[count.index].id
  network_id = local.network_id
  ip         = "10.0.1.${10 + count.index}"
}

# Talos needs ~60s after boot before accepting API connections
resource "time_sleep" "wait_for_talos_cp" {
  depends_on      = [hcloud_server_network.control_plane]
  create_duration = "60s"
}

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${hcloud_load_balancer_network.k8s_api.ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = concat([
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda"
          image = local.talos_image_id
        }
        certSANs = [
          hcloud_load_balancer_network.k8s_api.ip,
          "127.0.0.1",
        ]
        kubelet = {
          extraArgs = {
            "cloud-provider" = "external"
          }
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = false
        network = {
          cni = {
            name = "none"
          }
          podSubnets     = [var.pod_cidr]
          serviceSubnets = [var.service_cidr]
        }
        proxy = {
          disabled = true
        }
        externalCloudProvider = {
          enabled = true
          manifests = [
            "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v${var.hcloud_ccm_version}/ccm-networks.yaml"
          ]
        }
        inlineManifests = [
          {
            name = "hcloud-secret"
            contents = yamlencode({
              apiVersion = "v1"
              kind       = "Secret"
              metadata = {
                name      = "hcloud"
                namespace = "kube-system"
              }
              type = "Opaque"
              stringData = {
                token   = var.hcloud_token
                network = local.network_name
              }
            })
          },
        ]
      }
    })
  ], var.control_plane_extra_patches)
}

resource "talos_machine_configuration_apply" "controlplane" {
  count = var.control_plane_count

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  endpoint                    = hcloud_server.control_plane[count.index].ipv4_address
  node                        = hcloud_server_network.control_plane[count.index].ip

  depends_on = [
    time_sleep.wait_for_talos_cp,
    hcloud_server_network.control_plane,
    hcloud_load_balancer_network.k8s_api,
  ]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = hcloud_server.control_plane[0].ipv4_address
  node                 = hcloud_server_network.control_plane[0].ip

  depends_on = [talos_machine_configuration_apply.controlplane]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = hcloud_server.control_plane[0].ipv4_address
  node                 = hcloud_server_network.control_plane[0].ip

  depends_on = [talos_machine_bootstrap.this]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for n in hcloud_server_network.control_plane : n.ip]
  endpoints            = [for s in hcloud_server.control_plane : s.ipv4_address]
}

# Kubeconfig pointing to public CP IP for local-exec provisioners (bootstrap).
locals {
  deploy_kubeconfig_b64 = base64encode(replace(
    talos_cluster_kubeconfig.this.kubeconfig_raw,
    "https://${hcloud_load_balancer_network.k8s_api.ip}:6443",
    "https://${hcloud_server.control_plane[0].ipv4_address}:6443"
  ))
}
