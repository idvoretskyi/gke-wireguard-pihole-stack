# Kubernetes Namespaces

# Namespace for VPN services (WireGuard)
resource "kubernetes_namespace" "vpn" {
  metadata {
    name = "vpn"
    labels = {
      name        = "vpn"
      environment = var.environment
    }
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Namespace for DNS services (Pi-hole)
resource "kubernetes_namespace" "dns" {
  metadata {
    name = "dns"
    labels = {
      name        = "dns"
      environment = var.environment
    }
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Persistent Volume Claim for Pi-hole data
resource "kubernetes_persistent_volume_claim" "pihole_data" {
  metadata {
    name      = "pihole-data"
    namespace = kubernetes_namespace.dns.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    
    resources {
      requests = {
        storage = var.pihole_storage_size
      }
    }

    storage_class_name = "standard-rwo"
  }
}

# Secret for WireGuard admin password
resource "kubernetes_secret" "wireguard_admin" {
  metadata {
    name      = "wireguard-admin"
    namespace = kubernetes_namespace.vpn.metadata[0].name
  }

  data = {
    password = var.wireguard_admin_password
  }

  type = "Opaque"
}

# Secret for Pi-hole admin password
resource "kubernetes_secret" "pihole_admin" {
  metadata {
    name      = "pihole-admin"
    namespace = kubernetes_namespace.dns.metadata[0].name
  }

  data = {
    password = var.pihole_admin_password
  }

  type = "Opaque"
}
