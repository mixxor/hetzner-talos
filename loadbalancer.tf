resource "hcloud_load_balancer" "k8s_api" {
  name               = "${var.cluster_name}-api"
  load_balancer_type = "lb11"
  location           = var.location

  delete_protection = var.delete_protection

  labels = {
    role    = "k8s-api"
    cluster = var.cluster_name
  }
}

resource "hcloud_load_balancer_network" "k8s_api" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  network_id       = local.network_id
  ip               = "10.0.1.254"

  depends_on = [hcloud_network_subnet.control_plane]
}

resource "hcloud_load_balancer_service" "k8s_api" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_target" "control_plane" {
  count            = var.control_plane_count
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  server_id        = hcloud_server.control_plane[count.index].id
  use_private_ip   = true

  depends_on = [hcloud_load_balancer_network.k8s_api]
}
