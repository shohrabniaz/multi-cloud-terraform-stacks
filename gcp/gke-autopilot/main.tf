################################################################################
# GKE Autopilot
#
# Autopilot is GCP's "we run the nodes" mode. Per-pod billing, no node
# pool management. Closest GCP equivalent to the AWS Fargate / Azure
# Container Apps experience.
#
# When to pick this: small team, no GCP K8s expertise on staff, want
# Kubernetes API without operating the data plane.
################################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
  }
}

variable "project_id" { type = string }
variable "region"     { type = string }
variable "name"       { type = string }
variable "network"    { type = string }
variable "subnetwork" { type = string }
variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the control plane."
  type        = list(object({ cidr_block = string, display_name = string }))
  default     = []
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region

  enable_autopilot = true

  network    = var.network
  subnetwork = var.subnetwork

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    # Use the implicit secondary ranges set up on the subnet.
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = length(var.master_authorized_networks) == 0
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  resource_labels = {
    managed_by = "terraform"
    project    = var.name
  }

  # Autopilot creates and manages its own node SA; you don't pick the
  # machine type or autoscale settings — that's the point.
}

output "cluster_endpoint" {
  value     = google_container_cluster.this.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive = true
}
