# Post-apply health checks (warnings only, never block operations).

check "control_plane_private_network" {
  assert {
    condition = alltrue([
      for n in hcloud_server_network.control_plane : n.ip != ""
    ])
    error_message = "One or more control plane nodes do not have a private IP assigned."
  }
}

check "worker_private_network" {
  assert {
    condition = alltrue([
      for n in hcloud_server_network.worker : n.ip != ""
    ])
    error_message = "One or more worker nodes do not have a private IP assigned."
  }
}

check "control_plane_count" {
  assert {
    condition     = length(hcloud_server.control_plane) == var.control_plane_count
    error_message = "Expected ${var.control_plane_count} control plane nodes but ${length(hcloud_server.control_plane)} exist."
  }
}
