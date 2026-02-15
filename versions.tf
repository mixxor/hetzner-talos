terraform {
  required_version = ">= 1.11.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.60.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.13.1"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }
  }
}
