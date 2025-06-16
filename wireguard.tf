# WireGuard Deployment using wg-easy

# Add the wg-easy Helm repository
resource "helm_release" "wg_easy" {
  name       = "wg-easy"
  repository = "https://wg-easy.github.io/wg-easy"
  chart      = "wg-easy"
  version    = "~> 7.0"
  namespace  = kubernetes_namespace.vpn.metadata[0].name

  # Custom values for wg-easy configuration
  values = [
    yamlencode({
      # Image configuration
      image = {
        repository = "ghcr.io/wg-easy/wg-easy"
        tag        = "latest"
        pullPolicy = "IfNotPresent"
      }

      # Environment variables for wg-easy
      env = {
        # WireGuard configuration
        WG_HOST                = "" # Will be set to LoadBalancer IP automatically
        WG_PORT               = var.wireguard_port
        WG_DEFAULT_ADDRESS    = "10.8.0.x"
        WG_DEFAULT_DNS        = "10.2.0.10" # Pi-hole service IP (will be created)
        WG_ALLOWED_IPS        = "0.0.0.0/0"
        WG_PERSISTENT_KEEPALIVE = "25"
        
        # Web UI configuration
        PASSWORD              = var.wireguard_admin_password
        WG_ENABLE_ONE_TIME_LINKS = "true"
        
        # Advanced settings
        UI_TRAFFIC_STATS      = "true"
        UI_CHART_TYPE         = "1" # Line chart
      }

      # Service configuration
      service = {
        type = "LoadBalancer"
        ports = {
          web = {
            port       = 51821
            targetPort = 51821
            protocol   = "TCP"
          }
          wireguard = {
            port       = var.wireguard_port
            targetPort = var.wireguard_port
            protocol   = "UDP"
          }
        }
        annotations = {
          "cloud.google.com/load-balancer-type" = "External"
          # Uncomment to restrict access to specific IP ranges
          # "cloud.google.com/load-balancer-source-ranges" = "YOUR.IP.ADDRESS.HERE/32"
        }
      }

      # Persistence for WireGuard configuration
      persistence = {
        enabled      = true
        storageClass = "standard-rwo"
        size         = "1Gi"
        accessMode   = "ReadWriteOnce"
      }

      # Security context (required for WireGuard kernel module access)
      securityContext = {
        privileged = true
        capabilities = {
          add = [
            "NET_ADMIN",
            "SYS_MODULE"
          ]
        }
      }

      # Pod security context
      podSecurityContext = {
        sysctls = [
          {
            name  = "net.ipv4.ip_forward"
            value = "1"
          },
          {
            name  = "net.ipv4.conf.all.src_valid_mark"
            value = "1"
          }
        ]
      }

      # Resource limits and requests
      resources = {
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }

      # Node selector to ensure placement on nodes with kernel module support
      nodeSelector = {}

      # Tolerations for any taints on nodes
      tolerations = []

      # Affinity rules
      affinity = {}
    })
  ]

  # Wait for the VPN namespace to be ready
  depends_on = [
    kubernetes_namespace.vpn,
    kubernetes_secret.wireguard_admin
  ]
}

# Service to expose WireGuard web interface with a stable internal IP
resource "kubernetes_service" "wg_easy_internal" {
  metadata {
    name      = "wg-easy-internal"
    namespace = kubernetes_namespace.vpn.metadata[0].name
    labels = {
      app = "wg-easy"
    }
  }

  spec {
    type = "ClusterIP"
    
    selector = {
      "app.kubernetes.io/name"     = "wg-easy"
      "app.kubernetes.io/instance" = "wg-easy"
    }

    port {
      name        = "web"
      port        = 51821
      target_port = 51821
      protocol    = "TCP"
    }
  }

  depends_on = [helm_release.wg_easy]
}
