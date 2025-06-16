# GKE-Specific Requirements and Best Practices for WireGuard + Pi-hole

This document explains the specific Google Kubernetes Engine requirements and configurations needed for running WireGuard and Pi-hole effectively.

## GKE-Specific WireGuard Requirements

### 1. Kernel Module Support

**Challenge**: WireGuard requires kernel modules that may not be available in all GKE node images.

**Solution**: 
- Use Container-Optimized OS (COS) nodes (default in GKE)
- Enable privileged containers for WireGuard
- Use `NET_ADMIN` and `SYS_MODULE` capabilities

```hcl
# In Terraform configuration
securityContext = {
  privileged = true
  capabilities = {
    add = [
      "NET_ADMIN",
      "SYS_MODULE"
    ]
  }
}
```

### 2. Host Networking Considerations

**Challenge**: VPN traffic needs to be routed properly through GKE's network stack.

**Solutions**:
- Use LoadBalancer services with UDP support
- Configure proper firewall rules for VPN traffic
- Set up proper sysctls for IP forwarding

```hcl
# Required sysctls for WireGuard
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
```

### 3. Service Account Permissions

**Minimum required IAM roles for GKE nodes**:
- `roles/logging.logWriter` - For Cloud Logging
- `roles/monitoring.metricWriter` - For Cloud Monitoring
- `roles/monitoring.viewer` - For metric collection
- `roles/storage.objectViewer` - For pulling container images

### 4. Firewall Configuration

**Required firewall rules**:
```hcl
# WireGuard UDP traffic
resource "google_compute_firewall" "wireguard_udp" {
  name    = "wireguard-udp"
  network = google_compute_network.vpc.name

  allow {
    protocol = "udp"
    ports    = ["51820"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
}

# Web interfaces (HTTP/HTTPS)
resource "google_compute_firewall" "web_interfaces" {
  name    = "web-interfaces"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080", "51821"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
}
```

## Cost Optimization Strategies

### 1. Node Configuration

**Cheapest viable configuration**:
```hcl
# Ultra-low cost setup (personal use)
machine_type = "e2-micro"      # ~$6/month per instance
preemptible  = true            # 60-90% discount
disk_size_gb = 20              # Minimum viable
disk_type    = "pd-standard"   # Cheapest storage
```

**Recommended minimum for stability**:
```hcl
# Stable low-cost setup
machine_type = "e2-small"      # ~$15/month per instance
preemptible  = false           # More stable
disk_size_gb = 30              # Some headroom
disk_type    = "pd-standard"   # Still cost-effective
```

### 2. Cluster Management

**Use regional clusters for better availability**:
```hcl
# Regional cluster (multiple zones)
location = var.region  # e.g., "us-central1"
```

**Enable autoscaling**:
```hcl
autoscaling {
  min_node_count = 1
  max_node_count = 3
}
```

### 3. Storage Optimization

**Use regional persistent disks**:
```hcl
# More cost-effective than zonal disks
# Automatically replicated across zones
storage_class_name = "standard-rwo"
```

**Right-size storage**:
```hcl
# Pi-hole needs minimal storage
pihole_storage_size = "5Gi"  # Sufficient for most use cases
```

## Security Best Practices

### 1. Network Segmentation

**Use VPC-native clusters**:
```hcl
# IP allocation policy for VPC-native cluster
ip_allocation_policy {
  cluster_secondary_range_name  = "pods"
  services_secondary_range_name = "services"
}
```

**Enable network policies**:
```hcl
# Calico network policies
network_policy {
  enabled  = true
  provider = "CALICO"
}
```

### 2. Workload Identity

**Enable Workload Identity for secure pod authentication**:
```hcl
workload_identity_config {
  workload_pool = "${var.project_id}.svc.id.goog"
}
```

### 3. Private Cluster Configuration

**For enhanced security (optional)**:
```hcl
private_cluster_config {
  enable_private_nodes    = true
  enable_private_endpoint = false
  master_ipv4_cidr_block  = "172.16.0.0/28"
}
```

### 4. Master Authorized Networks

**Restrict cluster API access**:
```hcl
master_authorized_networks_config {
  cidr_blocks {
    cidr_block   = "YOUR.IP.ADDRESS/32"
    display_name = "Admin access"
  }
}
```

## Networking Architecture

### 1. VPC Design

```
┌─────────────────────────────────────────────────────────────┐
│ VPC Network (10.0.0.0/16)                                  │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Subnet (10.0.0.0/16)                                   │ │
│ │ ┌─────────────────┐ ┌─────────────────┐                │ │
│ │ │ Pods            │ │ Services        │                │ │
│ │ │ 10.1.0.0/16     │ │ 10.2.0.0/16     │                │ │
│ │ └─────────────────┘ └─────────────────┘                │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 2. Service Mesh

```
Internet
    │
    ▼
┌─────────────────┐
│ LoadBalancer    │
│ (External IP)   │
└─────────────────┘
    │
    ▼
┌─────────────────┐    ┌─────────────────┐
│ WireGuard       │    │ Pi-hole         │
│ (VPN Server)    │◄──►│ (DNS Filter)    │
└─────────────────┘    └─────────────────┘
    │                      │
    ▼                      ▼
┌─────────────────┐    ┌─────────────────┐
│ Persistent      │    │ Persistent      │
│ Storage         │    │ Storage         │
└─────────────────┘    └─────────────────┘
```

## Monitoring and Observability

### 1. GKE Built-in Monitoring

**Enable Cloud Monitoring integration**:
```hcl
monitoring_config {
  enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}
```

### 2. Logging Configuration

**Centralized logging**:
```hcl
logging_config {
  enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}
```

### 3. Custom Metrics

**Key metrics to monitor**:
- Pod CPU/Memory usage
- LoadBalancer health
- VPN connection count
- DNS query rates
- Storage utilization

## Disaster Recovery

### 1. Backup Strategy

**Automated Pi-hole backups**:
```bash
#!/bin/bash
# Script to backup Pi-hole configuration
kubectl exec -n dns deployment/pihole -- tar czf /tmp/pihole-backup.tar.gz /etc/pihole /etc/dnsmasq.d
kubectl cp dns/$(kubectl get pod -n dns -l app=pihole -o jsonpath='{.items[0].metadata.name}'):/tmp/pihole-backup.tar.gz ./backups/
```

### 2. Infrastructure as Code

**Benefits of Terraform**:
- Version-controlled infrastructure
- Reproducible deployments
- Easy disaster recovery
- Compliance and audit trails

### 3. Multi-Region Considerations

**For high availability**:
- Deploy to multiple regions
- Use global load balancers
- Replicate persistent storage
- Implement proper failover

## Compliance and Governance

### 1. GKE Binary Authorization

**Enable for production**:
```hcl
binary_authorization {
  evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
}
```

### 2. Pod Security Standards

**Implement security policies**:
```yaml
apiVersion: v1
kind: Pod
spec:
  securityContext:
    runAsNonRoot: false  # WireGuard needs root
    runAsUser: 0         # Required for VPN
    fsGroup: 0
  containers:
  - name: wireguard
    securityContext:
      privileged: true   # Required for kernel modules
```

### 3. Resource Governance

**Implement resource quotas**:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: vpn-quota
  namespace: vpn
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
```

## Performance Tuning

### 1. Node Optimization

**Optimize for VPN workloads**:
```hcl
# Use compute-optimized instances for high throughput
machine_type = "c2-standard-4"  # For high-performance VPN

# Enable local SSDs for better I/O
ephemeral_storage_local_ssd_config {
  local_ssd_count = 1
}
```

### 2. Network Optimization

**Tune network performance**:
```hcl
# Enable IP aliases for better performance
ip_allocation_policy {
  cluster_secondary_range_name  = "pods"
  services_secondary_range_name = "services"
}

# Use premium network tier
network_policy {
  enabled = true
}
```

### 3. Storage Performance

**Optimize storage for workloads**:
```hcl
# Use SSD persistent disks for better performance
disk_type = "pd-ssd"

# Enable automatic disk sizing
disk_size_gb = 100  # Larger for better IOPS
```

## Migration and Upgrades

### 1. GKE Cluster Upgrades

**Automated upgrades**:
```hcl
maintenance_policy {
  recurring_window {
    start_time = "2025-01-01T02:00:00Z"
    end_time   = "2025-01-01T06:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA"
  }
}
```

### 2. Application Updates

**Rolling updates**:
```bash
# Update container images
kubectl set image deployment/wg-easy wg-easy=ghcr.io/wg-easy/wg-easy:latest -n vpn
kubectl rollout status deployment/wg-easy -n vpn
```

### 3. Data Migration

**Persistent volume migration**:
```bash
# Create snapshot of existing volume
gcloud compute disks snapshot DISK_NAME --snapshot-names=pihole-backup

# Create new disk from snapshot
gcloud compute disks create new-pihole-disk --source-snapshot=pihole-backup
```

This comprehensive setup provides a production-ready, cost-optimized, and secure WireGuard + Pi-hole deployment on GKE with proper consideration of Google Cloud's specific requirements and best practices.
