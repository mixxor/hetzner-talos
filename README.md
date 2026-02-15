# Talos Kubernetes on Hetzner Cloud

> **Pre-alpha. Not tested in production.** This module was built as an
> experiment to explore self-hosted Kubernetes on Hetzner Cloud using
> Talos Linux and OpenTofu. It is not battle-tested, not feature-complete,
> and comes with no guarantees. Use it as a learning resource or starting
> point, not for production workloads.

OpenTofu module that deploys a
[Talos Linux](https://www.talos.dev/) Kubernetes cluster on Hetzner
Cloud with a single `tofu apply`.

No `helm` or `kubernetes` Terraform providers. Cilium, CCM, CSI, and
metrics server are installed via `local-exec` provisioners using
helm/kubectl CLI tools. This avoids the kubeconfig chicken-and-egg
problem that requires two-step applies in most other modules.

**Features:** multiple worker node pools with labels/taints, metrics
server, delete protection, and fully version-pinned components.

For a complete example with WireGuard VPN, ArgoCD, and etcd backups,
see [hetzner-talos-example](https://github.com/mixxor/hetzner-talos-example).

### Assumptions

- You have a Hetzner Cloud account and API token.
- You are comfortable with OpenTofu/Terraform and Kubernetes basics.
- CLI tools (`tofu`, `hcloud`, `helm`, `kubectl`, `jq`) are installed
  on your machine. The module calls them via `local-exec`.
- Servers use public IPs for initial bootstrap. The K8s API load
  balancer is private-only.
- The Talos snapshot is built automatically on first apply using
  Hetzner rescue mode. This takes a few minutes on the first run.
- The module creates its own network by default. Pass
  `hcloud_network_id` to use an existing one.

## Architecture

![Architecture](docs/architecture.svg)

The K8s API load balancer is private-only. During bootstrap, you
access the API via public CP IPs (firewalled to your IP). Pass
`firewall_allow_cidrs` to allow additional CIDRs (e.g. VPN).

## Quick Start

```hcl
module "cluster" {
  source       = "github.com/mixxor/hetzner-talos?ref=v0.1.0-alpha"
  hcloud_token = var.hcloud_token
}
```

```bash
tofu init && tofu apply
tofu output -raw kubeconfig_public > ~/.kube/hetzner
export KUBECONFIG=~/.kube/hetzner
kubectl get nodes
```

## Module Usage

### Minimal

```hcl
module "cluster" {
  source       = "github.com/mixxor/hetzner-talos?ref=v0.1.0-alpha"
  hcloud_token = var.hcloud_token

  cluster_name       = "my-cluster"
  kubernetes_version = "1.35.0"

  worker_nodepools = [{
    name        = "default"
    count       = 3
    server_type = "cx33"
    locations   = ["fsn1", "nbg1", "hel1"]
  }]
}
```

### Complete

```hcl
terraform {
  required_version = ">= 1.11.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.60.0"
    }
  }
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

provider "hcloud" {
  token = var.hcloud_token
}

module "cluster" {
  source       = "github.com/mixxor/hetzner-talos?ref=v0.1.0-alpha"
  hcloud_token = var.hcloud_token

  # Cluster
  cluster_name       = "staging"
  talos_version      = "v1.12.4"
  kubernetes_version = "1.35.0"
  talos_extensions   = [
    "siderolabs/qemu-guest-agent",
    "siderolabs/iscsi-tools",
    "siderolabs/util-linux-tools",
  ]

  # Control plane
  control_plane_count       = 3
  control_plane_server_type = "cx33"
  control_plane_locations   = ["fsn1", "nbg1", "hel1"]

  # Workers
  worker_nodepools = [
    {
      name        = "general"
      count       = 3
      server_type = "cx33"
      locations   = ["fsn1", "nbg1", "hel1"]
    },
    {
      name        = "general"
      count       = 3
      server_type = "cx33"
      locations   = ["nbg1"]
      labels      = { "workload" = "general" }
    },
    {
      name        = "db"
      count       = 2
      server_type = "cx43"
      locations   = ["fsn1"]
      labels      = { "workload" = "database" }
      taints      = ["dedicated=database:NoSchedule"]
    },
  ]

  # Network
  location                = "fsn1"
  network_zone            = "eu-central"
  network_cidr            = "10.0.0.0/8"
  control_plane_subnet_cidr = "10.0.1.0/24"
  worker_subnet_cidr      = "10.0.2.0/24"
  pod_cidr                = "10.244.0.0/16"
  service_cidr            = "10.96.0.0/12"

  # Firewall: allow VPN clients to reach K8s/Talos APIs
  firewall_allow_cidrs = ["10.100.0.0/24"]

  # Component versions
  cilium_version         = "1.19.0"
  hcloud_ccm_version     = "1.30.0"
  hcloud_csi_version     = "2.19.0"
  metrics_server_version = "3.13.0"

  # Toggles
  enable_csi        = true
  delete_protection = true

  # Extra Talos machine config patches
  control_plane_extra_patches = [
    yamlencode({
      machine = {
        sysctls = { "vm.max_map_count" = "262144" }
      }
    }),
  ]
  worker_extra_patches = [
    yamlencode({
      machine = {
        sysctls = { "net.core.somaxconn" = "65535" }
      }
    }),
  ]
}

# Outputs
output "kubeconfig" {
  value     = module.cluster.kubeconfig_public
  sensitive = true
}

output "talosconfig" {
  value     = module.cluster.talosconfig
  sensitive = true
}

output "control_plane_ips" {
  value = module.cluster.control_plane_ips
}

output "cluster_summary" {
  value = module.cluster.cluster_summary
}
```

### With existing network

```hcl
module "cluster" {
  source            = "github.com/mixxor/hetzner-talos?ref=v0.1.0-alpha"
  hcloud_token      = var.hcloud_token
  hcloud_network_id = hcloud_network.shared.id
}
```

## Standalone Usage

```bash
cp terraform.tfvars.example terraform.tfvars  # adjust as needed
export TF_VAR_hcloud_token="your-token"

tofu init && tofu apply

tofu output -raw kubeconfig_public > ~/.kube/hetzner
export KUBECONFIG=~/.kube/hetzner
kubectl get nodes
```

## Talos Image

Uses [Image Factory](https://factory.talos.dev/) to build a custom
Talos image with the extensions specified in `talos_extensions`. The
schematic ID is generated automatically by the
`talos_image_factory_schematic` resource.

The Hetzner snapshot is created automatically during `tofu apply` if
one doesn't already exist. A temporary server boots into rescue mode,
downloads the image, writes it with `dd conv=fsync`, and snapshots
the disk. Subsequent applies reuse the existing snapshot by label.

## Worker Node Pools

Define multiple node pools with different server types, locations,
labels, and taints:

```hcl
worker_nodepools = [
  {
    name        = "default"
    count       = 3
    server_type = "cx33"
    locations   = ["fsn1", "nbg1", "hel1"]
  },
  {
    name        = "db"
    count       = 2
    server_type = "cx43"
    locations   = ["fsn1"]
    labels      = { "workload" = "database" }
    taints      = ["dedicated=database:NoSchedule"]
  },
]
```

Each pool gets its own placement group. Labels are applied as
Kubernetes node labels, taints via kubelet `--register-with-taints`.

## Troubleshooting

**Can't reach the cluster** -- Use `kubeconfig_public` output.

**Nodes stuck in NotReady** -- Usually Cilium or CCM. Check
`kubectl -n kube-system get pods` and look at logs for `cilium`
or `hcloud-cloud-controller-manager`.

**DNS broken in pods** -- Cilium is configured with
`bpf.hostLegacyRouting=true` to work around
[siderolabs/talos#10002](https://github.com/siderolabs/talos/issues/10002).
If you changed Cilium values, make sure this is still set.

**Rotated Hetzner API token** -- The hcloud token is baked into the
Talos machine config as a Kubernetes Secret (inline manifest). Run
`tofu apply` to re-apply the machine config with the new token.
Alternatively, update it manually:

```bash
kubectl -n kube-system create secret generic hcloud \
  --from-literal=token="NEW_TOKEN" \
  --from-literal=network="$(kubectl -n kube-system get secret hcloud -o jsonpath='{.data.network}' | base64 -d)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kube-system rollout restart deployment/hcloud-cloud-controller-manager
```

## Upgrading

All versions are controlled via variables. Update the relevant
variable and run `tofu apply`.

**Kubernetes version** -- update `kubernetes_version`. The Talos
provider re-applies the machine config and Talos handles the
rolling upgrade.

**Talos version** -- update `talos_version`. A new snapshot is
built automatically. Existing nodes upgrade via the installer image
reference in the machine config; the snapshot is only used for new
servers.

**Component versions** -- update `cilium_version`,
`hcloud_ccm_version`, `hcloud_csi_version`, or
`metrics_server_version`. The corresponding `terraform_data`
resource re-runs `helm upgrade` when the version changes.

**Talos extensions** -- add or remove entries in `talos_extensions`.
A new schematic and snapshot are built on the next apply.

Check the
[Talos support matrix](https://www.talos.dev/latest/introduction/support-matrix/)
for compatible Kubernetes versions before upgrading.

## Tear Down

```bash
tofu destroy
```

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.11
- [hcloud CLI](https://github.com/hetznercloud/cli)
- [Helm](https://helm.sh/docs/intro/install/)
- [jq](https://jqlang.github.io/jq/)
- Hetzner Cloud API token

## Development

```bash
pre-commit install
tofu fmt -recursive
tofu validate
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| hcloud\_token | Hetzner Cloud API token - set via TF\_VAR\_hcloud\_token env var | `string` | n/a | yes |
| cilium\_version | Cilium Helm chart version | `string` | `"1.19.0"` | no |
| cluster\_name | Name of the Kubernetes cluster | `string` | `"talos-k8s"` | no |
| control\_plane\_count | Number of control plane nodes (must be odd for etcd quorum) | `number` | `3` | no |
| control\_plane\_extra\_patches | Additional Talos machine config patches for control plane nodes (list of YAML strings) | `list(string)` | `[]` | no |
| control\_plane\_locations | Locations for control plane nodes (distributed for HA) | `list(string)` | <pre>[<br/>  "fsn1",<br/>  "nbg1",<br/>  "hel1"<br/>]</pre> | no |
| control\_plane\_server\_type | Hetzner server type for control plane nodes | `string` | `"cx33"` | no |
| control\_plane\_subnet\_cidr | Control plane subnet CIDR | `string` | `"10.0.1.0/24"` | no |
| delete\_protection | Enable Hetzner delete/rebuild protection on servers, LB, and network | `bool` | `false` | no |
| enable\_csi | Install Hetzner CSI driver (set to false to manage it externally via Helm/ArgoCD) | `bool` | `true` | no |
| firewall\_allow\_cidrs | CIDR ranges allowed to access K8s and Talos APIs externally. Auto-detects deployer's public IP if empty. | `list(string)` | `[]` | no |
| hcloud\_ccm\_version | Hetzner Cloud Controller Manager version | `string` | `"1.30.0"` | no |
| hcloud\_csi\_version | Hetzner CSI driver Helm chart version | `string` | `"2.19.0"` | no |
| hcloud\_network\_id | ID of an existing Hetzner network to use. If null, a new network is created. | `number` | `null` | no |
| kubernetes\_version | Kubernetes version | `string` | `"1.35.0"` | no |
| location | Primary Hetzner datacenter location | `string` | `"fsn1"` | no |
| metrics\_server\_version | Metrics Server Helm chart version | `string` | `"3.13.0"` | no |
| network\_cidr | Main network CIDR (only used when creating a new network) | `string` | `"10.0.0.0/8"` | no |
| network\_zone | Hetzner network zone | `string` | `"eu-central"` | no |
| pod\_cidr | Pod network CIDR | `string` | `"10.244.0.0/16"` | no |
| service\_cidr | Service network CIDR | `string` | `"10.96.0.0/12"` | no |
| talos\_extensions | Talos system extensions to include (see https://factory.talos.dev/) | `list(string)` | <pre>[<br/>  "siderolabs/qemu-guest-agent",<br/>  "siderolabs/iscsi-tools",<br/>  "siderolabs/util-linux-tools"<br/>]</pre> | no |
| talos\_version | Talos Linux version | `string` | `"v1.12.4"` | no |
| worker\_extra\_patches | Additional Talos machine config patches for worker nodes (list of YAML strings) | `list(string)` | `[]` | no |
| worker\_nodepools | Worker node pools. Each pool can have its own server type, locations, count, labels, and taints. | <pre>list(object({<br/>    name        = string<br/>    count       = number<br/>    server_type = string<br/>    locations   = list(string)<br/>    labels      = optional(map(string), {})<br/>    taints      = optional(list(string), [])<br/>  }))</pre> | <pre>[<br/>  {<br/>    "count": 3,<br/>    "locations": [<br/>      "fsn1",<br/>      "nbg1",<br/>      "hel1"<br/>    ],<br/>    "name": "default",<br/>    "server_type": "cx33"<br/>  }<br/>]</pre> | no |
| worker\_subnet\_cidr | Worker subnet CIDR | `string` | `"10.0.2.0/24"` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster\_ready | Readiness marker — all core components (Cilium, CCM, CSI, metrics-server) are deployed. Use depends\_on with this output. |
| cluster\_summary | Summary of deployed resources |
| connection\_info | Connection information for the cluster |
| control\_plane\_ips | Public IPs of control plane nodes |
| control\_plane\_private\_ips | Private IPs of control plane nodes |
| firewall\_allowed\_cidrs | CIDR ranges allowed in firewall for K8s/Talos API access |
| k8s\_api\_lb\_ip | Private IP of the Kubernetes API load balancer |
| kubeconfig | Kubeconfig for kubectl access (uses private LB IP) |
| kubeconfig\_public | Kubeconfig using public CP IP (direct access) |
| network\_id | Hetzner network ID used by the cluster |
| network\_name | Hetzner network name used by the cluster |
| talos\_snapshot\_id | Hetzner Cloud snapshot ID for Talos |
| talosconfig | Talosconfig for talosctl access |
| worker\_ips | Public IPs of worker nodes (keyed by pool-index) |
| worker\_private\_ips | Private IPs of worker nodes (keyed by pool-index) |
<!-- END_TF_DOCS -->
