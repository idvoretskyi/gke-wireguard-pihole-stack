# Pi-hole DNS Adblocker Deployment

# Pi-hole Helm release using the community chart
resource "helm_release" "pihole" {
  name       = "pihole"
  repository = "https://mojo2600.github.io/pihole-kubernetes/"
  chart      = "pihole"
  version    = "~> 2.18"
  namespace  = kubernetes_namespace.dns.metadata[0].name

  # Custom values for Pi-hole configuration
  values = [
    yamlencode({
      # Image configuration
      image = {
        repository = "pihole/pihole"
        tag        = "latest"
        pullPolicy = "IfNotPresent"
      }

      # Pi-hole environment configuration
      admin = {
        enabled          = true
        existingSecret   = kubernetes_secret.pihole_admin.metadata[0].name
        passwordKey      = "password"
      }

      # DNS configuration
      DNS1 = "1.1.1.1"         # Cloudflare DNS
      DNS2 = "1.0.0.1"         # Cloudflare DNS backup
      
      # Pi-hole specific settings
      WEBPASSWORD = ""  # Will use existing secret
      TZ         = "UTC"
      DNSMASQ_USER = "root"
      
      # Virtual host for web interface
      VIRTUAL_HOST = "pihole.local"
      
      # Enable query logging
      QUERY_LOGGING = true
      
      # Install recommended packages
      INSTALL_WEB_SERVER = true
      INSTALL_WEB_INTERFACE = true
      LIGHTTPD_ENABLED = true

      # Service configuration
      serviceTCP = {
        enabled = true
        type    = "LoadBalancer"
        port    = 80
        targetPort = 80
        annotations = {
          "cloud.google.com/load-balancer-type" = "External"
          # Uncomment to restrict access to specific IP ranges
          # "cloud.google.com/load-balancer-source-ranges" = "YOUR.IP.ADDRESS.HERE/32"
        }
      }

      serviceUDP = {
        enabled = true
        type    = "LoadBalancer"
        port    = 53
        targetPort = 53
        annotations = {
          "cloud.google.com/load-balancer-type" = "External"
        }
      }

      # Persistence configuration
      persistentVolumeClaim = {
        enabled      = true
        existingClaim = kubernetes_persistent_volume_claim.pihole_data.metadata[0].name
      }

      # Additional volumes for custom configurations
      extraVolumes = []
      extraVolumeMounts = []

      # Pod security context
      podSecurityContext = {
        fsGroup = 999
      }

      # Container security context
      securityContext = {
        runAsUser  = 999
        runAsGroup = 999
        capabilities = {
          add = [
            "NET_BIND_SERVICE",
            "CHOWN",
            "SETUID",
            "SETGID"
          ]
        }
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

      # Probes for health checking
      probes = {
        liveness = {
          enabled             = true
          initialDelaySeconds = 60
          failureThreshold    = 10
          timeoutSeconds      = 5
          httpGet = {
            path   = "/admin/"
            port   = 80
            scheme = "HTTP"
          }
        }
        readiness = {
          enabled             = true
          initialDelaySeconds = 60
          failureThreshold    = 3
          timeoutSeconds      = 5
          httpGet = {
            path   = "/admin/"
            port   = 80
            scheme = "HTTP"
          }
        }
      }

      # Node placement
      nodeSelector = {}
      tolerations  = []
      affinity     = {}

      # Pod Disruption Budget
      podDisruptionBudget = {
        enabled      = false
        minAvailable = 1
      }

      # Monitoring and metrics
      monitoring = {
        podMonitor = {
          enabled = false
        }
        sidecar = {
          enabled = false
        }
      }

      # Additional environment variables
      extraEnvVars = [
        {
          name  = "PIHOLE_UID"
          value = "999"
        },
        {
          name  = "PIHOLE_GID"
          value = "999"
        }
      ]
    })
  ]

  # Wait for dependencies
  depends_on = [
    kubernetes_namespace.dns,
    kubernetes_persistent_volume_claim.pihole_data,
    kubernetes_secret.pihole_admin
  ]
}

# Service with fixed ClusterIP for Pi-hole DNS
resource "kubernetes_service" "pihole_dns" {
  metadata {
    name      = "pihole-dns"
    namespace = kubernetes_namespace.dns.metadata[0].name
    labels = {
      app = "pihole"
    }
  }

  spec {
    type       = "ClusterIP"
    cluster_ip = "10.2.0.10"  # Fixed IP for DNS resolution
    
    selector = {
      app     = "pihole"
      release = "pihole"
    }

    port {
      name        = "dns-tcp"
      port        = 53
      target_port = 53
      protocol    = "TCP"
    }

    port {
      name        = "dns-udp"
      port        = 53
      target_port = 53
      protocol    = "UDP"
    }
  }

  depends_on = [helm_release.pihole]
}

# ConfigMap for custom Pi-hole configuration
resource "kubernetes_config_map" "pihole_custom_config" {
  metadata {
    name      = "pihole-custom-config"
    namespace = kubernetes_namespace.dns.metadata[0].name
  }

  data = {
    "custom.list" = <<-EOF
      # Custom DNS entries for local services
      # Add your custom DNS entries here
      # Example: 192.168.1.100 myserver.local
    EOF
    
    "adlists.list" = <<-EOF
      # Additional blocklists for Pi-hole
      https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
      https://someonewhocares.org/hosts/zero/hosts
      https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt
    EOF
  }

  depends_on = [kubernetes_namespace.dns]
}

# Network Policy to allow DNS traffic (if network policies are enabled)
resource "kubernetes_network_policy" "pihole_dns_policy" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "pihole-dns-policy"
    namespace = kubernetes_namespace.dns.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app     = "pihole"
        release = "pihole"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {}
      }
      
      ports {
        protocol = "TCP"
        port     = "53"
      }
      
      ports {
        protocol = "UDP"
        port     = "53"
      }
      
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    egress {
      # Allow all outbound traffic for DNS resolution and updates
      to {}
      ports {
        protocol = "TCP"
        port     = "443"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
  }
}
