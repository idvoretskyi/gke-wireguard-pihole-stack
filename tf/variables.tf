# Terraform Variables for GKE WireGuard + Pi-hole Stack

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for the GKE cluster and related resources"
  type        = string
  default     = "us-central1"
}

variable "zones" {
  description = "The GCP zones for the GKE cluster nodes"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b"]
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "wireguard-cluster"
}

variable "node_pool_name" {
  description = "Name of the primary node pool"
  type        = string
  default     = "primary-pool"
}

variable "machine_type" {
  description = "Machine type for GKE nodes (e2-micro for cost optimization)"
  type        = string
  default     = "e2-micro"
}

variable "node_count" {
  description = "Number of nodes in the node pool"
  type        = number
  default     = 2
}

variable "max_node_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 3
}

variable "min_node_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 1
}

variable "preemptible" {
  description = "Use preemptible nodes for cost savings (not recommended for production)"
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Disk size for each node in GB"
  type        = number
  default     = 20
}

variable "disk_type" {
  description = "Disk type for nodes (pd-standard for cost optimization)"
  type        = string
  default     = "pd-standard"
}

variable "wireguard_admin_password" {
  description = "Admin password for WireGuard wg-easy interface"
  type        = string
  sensitive   = true
  default     = "ChangeMePlease123!"
}

variable "pihole_admin_password" {
  description = "Admin password for Pi-hole web interface"
  type        = string
  sensitive   = true
  default     = "ChangeMePlease123!"
}

variable "enable_network_policy" {
  description = "Enable Kubernetes Network Policy (Calico)"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable GKE Workload Identity for enhanced security"
  type        = bool
  default     = true
}

variable "enable_private_nodes" {
  description = "Enable private nodes (nodes have no public IP)"
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "List of authorized networks that can access the cluster master"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  ]
}

variable "wireguard_port" {
  description = "UDP port for WireGuard VPN"
  type        = number
  default     = 51820
}

variable "pihole_storage_size" {
  description = "Storage size for Pi-hole persistent volume"
  type        = string
  default     = "5Gi"
}

variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default = {
    "terraform" = "true"
    "project"   = "wireguard-pihole"
  }
}
