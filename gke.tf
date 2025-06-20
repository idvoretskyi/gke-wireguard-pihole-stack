# GKE Cluster Configuration

# Service account for GKE nodes
resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node Service Account for ${var.cluster_name}"
  description  = "Service account used by GKE nodes in the ${var.cluster_name} cluster"
}

# IAM bindings for the GKE node service account
# These are the minimum required roles for GKE nodes
resource "google_project_iam_member" "gke_node_sa_bindings" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/storage.objectViewer",
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# VPC Network for the GKE cluster
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  description             = "VPC network for ${var.cluster_name} cluster"
}

# Subnet for the GKE cluster
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc.id
  description   = "Subnet for ${var.cluster_name} GKE cluster"

  # Secondary IP ranges for pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }

  # Enable private Google access for nodes without external IPs
  private_ip_google_access = true
}

# Cloud Router for NAT Gateway (required for private nodes)
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT for outbound internet access from private nodes
resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  
  # Remove default node pool immediately after cluster creation
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network configuration
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # IP allocation policy for VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Enable Workload Identity for enhanced security
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable network policy (Calico) for pod-to-pod security
  network_policy {
    enabled  = var.enable_network_policy
    provider = var.enable_network_policy ? "CALICO" : null
  }

  # Addons configuration
  addons_config {
    # Enable HTTP load balancing for ingress
    http_load_balancing {
      disabled = false
    }

    # Enable horizontal pod autoscaling
    horizontal_pod_autoscaling {
      disabled = false
    }

    # Enable network policy enforcement
    network_policy_config {
      disabled = !var.enable_network_policy
    }

    # Enable DNS cache for better performance
    dns_cache_config {
      enabled = true
    }
  }

  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.enable_private_nodes ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = false
      master_ipv4_cidr_block  = "172.16.0.0/28"
    }
  }

  # Master authorized networks
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Enable legacy ABAC is disabled by default (good security practice)
  enable_legacy_abac = false

  # Enable binary authorization (recommended for production)
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Maintenance policy
  maintenance_policy {
    recurring_window {
      start_time = "2025-01-01T02:00:00Z"
      end_time   = "2025-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  # Resource labels
  resource_labels = merge(var.tags, {
    environment = var.environment
    cluster     = var.cluster_name
  })

  depends_on = [
    google_project_iam_member.gke_node_sa_bindings,
  ]
}

# Primary Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = var.node_pool_name
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  # Autoscaling configuration
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  # Node configuration
  node_config {
    # Use preemptible instances for cost savings (not recommended for production)
    preemptible  = var.preemptible
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type

    # Service account for nodes
    service_account = google_service_account.gke_node_sa.email

    # OAuth scopes for the service account
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/storage-ro",
    ]

    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Tags for firewall rules
    tags = ["gke-node", "${var.cluster_name}-node"]

    # Labels
    labels = merge(var.tags, {
      environment = var.environment
      node-pool   = var.node_pool_name
    })

    # Workload Identity configuration
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Shielded instance configuration for security
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # Management configuration
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [
    google_container_cluster.primary,
  ]
}

# Firewall rule to allow WireGuard UDP traffic
resource "google_compute_firewall" "wireguard_udp" {
  name    = "${var.cluster_name}-wireguard-udp"
  network = google_compute_network.vpc.name

  allow {
    protocol = "udp"
    ports    = [tostring(var.wireguard_port)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]

  description = "Allow WireGuard UDP traffic on port ${var.wireguard_port}"
}

# Firewall rule to allow HTTP/HTTPS traffic for web interfaces
resource "google_compute_firewall" "web_interfaces" {
  name    = "${var.cluster_name}-web-interfaces"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080", "8443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]

  description = "Allow HTTP/HTTPS traffic for WireGuard and Pi-hole web interfaces"
}

# Firewall rule for SSH access (optional, for debugging)
resource "google_compute_firewall" "ssh" {
  name    = "${var.cluster_name}-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]

  description = "Allow SSH access to GKE nodes (for debugging)"
}
