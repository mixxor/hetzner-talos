locals {
  worker_nodes = merge([
    for pool_idx, pool in var.worker_nodepools : {
      for i in range(pool.count) : "${pool.name}-${i}" => {
        pool_name   = pool.name
        server_type = pool.server_type
        location    = pool.locations[i % length(pool.locations)]
        labels      = pool.labels
        taints      = pool.taints
      }
    }
  ]...)
}

resource "hcloud_placement_group" "worker" {
  for_each = { for pool in var.worker_nodepools : pool.name => pool }
  name     = "${var.cluster_name}-worker-${each.key}"
  type     = "spread"

  labels = {
    role    = "worker"
    pool    = each.key
    cluster = var.cluster_name
  }
}

resource "hcloud_server" "worker" {
  for_each    = local.worker_nodes
  name        = "${var.cluster_name}-worker-${each.key}"
  server_type = each.value.server_type
  image       = local.talos_snapshot_id
  location    = each.value.location

  delete_protection  = var.delete_protection
  rebuild_protection = var.delete_protection

  placement_group_id = hcloud_placement_group.worker[each.value.pool_name].id

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  firewall_ids = [
    hcloud_firewall.cluster.id,
    hcloud_firewall.workers.id,
  ]

  labels = merge(
    {
      role    = "worker"
      pool    = each.value.pool_name
      cluster = var.cluster_name
    },
    each.value.labels,
  )

  depends_on = [hcloud_network_subnet.workers]
}

resource "hcloud_server_network" "worker" {
  for_each   = local.worker_nodes
  server_id  = hcloud_server.worker[each.key].id
  network_id = local.network_id
}

# Talos needs ~60s after boot before accepting API connections
resource "time_sleep" "wait_for_talos_worker" {
  depends_on      = [hcloud_server_network.worker]
  create_duration = "60s"
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${hcloud_load_balancer_network.k8s_api.ip}:6443"
  machine_type     = "worker"
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
        kubelet = {
          extraArgs = {
            "cloud-provider" = "external"
          }
          extraMounts = [
            {
              destination = "/var/mnt/longhorn"
              type        = "bind"
              source      = "/var/mnt/longhorn"
              options     = ["bind", "rshared", "rw"]
            }
          ]
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
      }
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ], var.worker_extra_patches)
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  endpoint                    = hcloud_server.worker[each.key].ipv4_address
  node                        = hcloud_server_network.worker[each.key].ip

  config_patches = concat(
    [yamlencode({
      machine = {
        nodeLabels = merge(
          { "node.kubernetes.io/pool" = each.value.pool_name },
          each.value.labels,
        )
      }
    })],
    length(each.value.taints) > 0 ? [yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            "register-with-taints" = join(",", each.value.taints)
          }
        }
      }
    })] : [],
  )

  depends_on = [
    time_sleep.wait_for_talos_worker,
    talos_machine_bootstrap.this,
  ]
}
