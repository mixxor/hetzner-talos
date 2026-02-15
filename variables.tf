variable "hcloud_token" {
  description = "Hetzner Cloud API token - set via TF_VAR_hcloud_token env var"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "talos-k8s"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be lowercase alphanumeric with hyphens, 3-63 characters."
  }
}

variable "talos_version" {
  description = "Talos Linux version"
  type        = string
  default     = "v1.12.4"

  validation {
    condition     = startswith(var.talos_version, "v")
    error_message = "Talos version must start with 'v' (e.g. v1.12.4)."
  }
}

variable "talos_extensions" {
  description = "Talos system extensions to include (see https://factory.talos.dev/)"
  type        = list(string)
  default     = ["siderolabs/qemu-guest-agent", "siderolabs/iscsi-tools", "siderolabs/util-linux-tools"]
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35.0"
}

variable "control_plane_count" {
  description = "Number of control plane nodes (must be odd for etcd quorum)"
  type        = number
  default     = 3

  validation {
    condition     = var.control_plane_count >= 1 && var.control_plane_count % 2 == 1
    error_message = "Control plane count must be an odd number >= 1 for etcd quorum."
  }
}

variable "control_plane_server_type" {
  description = "Hetzner server type for control plane nodes"
  type        = string
  default     = "cx33"
}

variable "location" {
  description = "Primary Hetzner datacenter location"
  type        = string
  default     = "fsn1"
}

variable "control_plane_locations" {
  description = "Locations for control plane nodes (distributed for HA)"
  type        = list(string)
  default     = ["fsn1", "nbg1", "hel1"]

  validation {
    condition     = length(var.control_plane_locations) >= 1
    error_message = "At least one control plane location must be specified."
  }

  validation {
    condition     = length(var.control_plane_locations) <= var.control_plane_count
    error_message = "Cannot have more locations than control plane nodes."
  }
}

variable "worker_nodepools" {
  description = "Worker node pools. Each pool can have its own server type, locations, count, labels, and taints."
  type = list(object({
    name        = string
    count       = number
    server_type = string
    locations   = list(string)
    labels      = optional(map(string), {})
    taints      = optional(list(string), [])
  }))
  default = [{
    name        = "default"
    count       = 3
    server_type = "cx33"
    locations   = ["fsn1", "nbg1", "hel1"]
  }]
}

variable "network_zone" {
  description = "Hetzner network zone"
  type        = string
  default     = "eu-central"
}

variable "hcloud_network_id" {
  description = "ID of an existing Hetzner network to use. If null, a new network is created."
  type        = number
  default     = null
}

variable "network_cidr" {
  description = "Main network CIDR (only used when creating a new network)"
  type        = string
  default     = "10.0.0.0/8"

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be valid CIDR notation."
  }
}

variable "control_plane_subnet_cidr" {
  description = "Control plane subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "worker_subnet_cidr" {
  description = "Worker subnet CIDR"
  type        = string
  default     = "10.0.2.0/24"
}

variable "pod_cidr" {
  description = "Pod network CIDR"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service network CIDR"
  type        = string
  default     = "10.96.0.0/12"
}

variable "firewall_allow_cidrs" {
  description = "CIDR ranges allowed to access K8s and Talos APIs externally. Auto-detects deployer's public IP if empty."
  type        = list(string)
  default     = []
}

# --- Component toggles ---

variable "enable_csi" {
  description = "Install Hetzner CSI driver (set to false to manage it externally via Helm/ArgoCD)"
  type        = bool
  default     = true
}

# --- Component versions ---

variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.0"
}

variable "hcloud_ccm_version" {
  description = "Hetzner Cloud Controller Manager version"
  type        = string
  default     = "1.30.0"
}

variable "hcloud_csi_version" {
  description = "Hetzner CSI driver Helm chart version"
  type        = string
  default     = "2.19.0"
}

variable "metrics_server_version" {
  description = "Metrics Server Helm chart version"
  type        = string
  default     = "3.13.0"
}

# --- Config patch passthrough ---

variable "control_plane_extra_patches" {
  description = "Additional Talos machine config patches for control plane nodes (list of YAML strings)"
  type        = list(string)
  default     = []
}

variable "worker_extra_patches" {
  description = "Additional Talos machine config patches for worker nodes (list of YAML strings)"
  type        = list(string)
  default     = []
}

# --- Protection ---

variable "delete_protection" {
  description = "Enable Hetzner delete/rebuild protection on servers, LB, and network"
  type        = bool
  default     = false
}
