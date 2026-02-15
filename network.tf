data "http" "local_ip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  # Always include deployer's IP + any extra CIDRs (e.g. VPN)
  deployer_cidrs          = ["${trimspace(data.http.local_ip.response_body)}/32"]
  firewall_external_cidrs = distinct(concat(local.deployer_cidrs, var.firewall_allow_cidrs))

  # Network: use existing or created
  network_id   = var.hcloud_network_id != null ? data.hcloud_network.existing[0].id : hcloud_network.cluster[0].id
  network_name = var.hcloud_network_id != null ? data.hcloud_network.existing[0].name : hcloud_network.cluster[0].name
  network_cidr = var.hcloud_network_id != null ? data.hcloud_network.existing[0].ip_range : var.network_cidr
}

# --- Network ---

resource "hcloud_network" "cluster" {
  count    = var.hcloud_network_id == null ? 1 : 0
  name     = "${var.cluster_name}-network"
  ip_range = var.network_cidr
}

data "hcloud_network" "existing" {
  count = var.hcloud_network_id != null ? 1 : 0
  id    = var.hcloud_network_id
}

resource "hcloud_network_subnet" "control_plane" {
  network_id   = local.network_id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.control_plane_subnet_cidr
}

resource "hcloud_network_subnet" "workers" {
  network_id   = local.network_id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.worker_subnet_cidr
}

# --- Firewalls ---

resource "hcloud_firewall" "cluster" {
  name = "${var.cluster_name}-cluster"

  # K8s API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = concat(local.firewall_external_cidrs, [local.network_cidr])
  }

  # Talos API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "50000-50001"
    source_ips = concat(local.firewall_external_cidrs, [local.network_cidr])
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2379-2380"
    source_ips = [var.control_plane_subnet_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = [local.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "30000-32767"
    source_ips = [local.network_cidr]
  }

  # Cilium VXLAN
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8472"
    source_ips = [local.network_cidr]
  }

  # Cilium health
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "4240"
    source_ips = [local.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall" "workers" {
  name = "${var.cluster_name}-workers"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}
