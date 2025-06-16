# Terraform Outputs

# GKE Cluster Information
output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.primary.location
}

output "cluster_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate of the GKE cluster"
  value       = google_container_cluster.primary.master_auth.0.cluster_ca_certificate
  sensitive   = true
}

# Network Information
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

# Service Account Information
output "node_service_account_email" {
  description = "Email of the GKE node service account"
  value       = google_service_account.gke_node_sa.email
}

# WireGuard Service Information
output "wireguard_namespace" {
  description = "Kubernetes namespace for WireGuard"
  value       = kubernetes_namespace.vpn.metadata[0].name
}

output "wireguard_service_name" {
  description = "Name of the WireGuard Helm release"
  value       = helm_release.wg_easy.name
}

# Pi-hole Service Information
output "pihole_namespace" {
  description = "Kubernetes namespace for Pi-hole"
  value       = kubernetes_namespace.dns.metadata[0].name
}

output "pihole_service_name" {
  description = "Name of the Pi-hole Helm release"
  value       = helm_release.pihole.name
}

output "pihole_dns_service_ip" {
  description = "Cluster IP of the Pi-hole DNS service"
  value       = kubernetes_service.pihole_dns.spec[0].cluster_ip
}

# kubectl Configuration Command
output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${google_container_cluster.primary.location} --project ${var.project_id}"
}

# Service Access Information
output "service_access_commands" {
  description = "Commands to get service external IPs"
  value = {
    wireguard_ip = "kubectl get svc wg-easy -n ${kubernetes_namespace.vpn.metadata[0].name} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    pihole_web_ip = "kubectl get svc pihole-serviceTCP -n ${kubernetes_namespace.dns.metadata[0].name} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    pihole_dns_ip = "kubectl get svc pihole-serviceUDP -n ${kubernetes_namespace.dns.metadata[0].name} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
  }
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, as of 2025)"
  value = {
    note = "Costs are estimates and may vary based on usage, region, and Google Cloud pricing changes"
    gke_cluster_management = "Free (GKE Autopilot management fee waived for zonal clusters)"
    compute_instances = "${var.preemptible ? "~$4-6" : "~$15-20"} per ${var.machine_type} instance per month"
    persistent_disks = "~$0.40 per GB per month for standard persistent disks"
    load_balancers = "~$18 per month per LoadBalancer"
    network_egress = "Variable based on VPN usage (~$0.12/GB to internet)"
    total_estimate = "${var.preemptible ? "$30-50" : "$60-80"} per month for minimal setup"
  }
}

# Security and Access Notes
output "security_notes" {
  description = "Important security configuration notes"
  value = {
    wireguard_admin_password = "Change the default WireGuard admin password immediately!"
    pihole_admin_password = "Change the default Pi-hole admin password immediately!"
    load_balancer_access = "Consider restricting LoadBalancer source IP ranges for better security"
    firewall_rules = "Review and adjust firewall rules based on your security requirements"
    workload_identity = "Workload Identity is ${var.enable_workload_identity ? "enabled" : "disabled"}"
    private_nodes = "Private nodes are ${var.enable_private_nodes ? "enabled" : "disabled"}"
    network_policy = "Network policies are ${var.enable_network_policy ? "enabled" : "disabled"}"
  }
}

# Client Configuration Instructions
output "client_setup_instructions" {
  description = "Instructions for setting up WireGuard clients"
  value = {
    step_1 = "Get WireGuard web UI IP: kubectl get svc wg-easy -n vpn -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    step_2 = "Access web UI at http://<WIREGUARD_IP>:51821"
    step_3 = "Login with the admin password you configured"
    step_4 = "Create client configurations in the web interface"
    step_5 = "Download client config files or scan QR codes"
    step_6 = "Import configs to WireGuard clients on your devices"
    dns_note = "Clients will automatically use Pi-hole for DNS (configured at 10.2.0.10)"
  }
}

# Pi-hole Configuration Instructions
output "pihole_setup_instructions" {
  description = "Instructions for configuring Pi-hole"
  value = {
    step_1 = "Get Pi-hole web UI IP: kubectl get svc pihole-serviceTCP -n dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    step_2 = "Access Pi-hole admin at http://<PIHOLE_IP>/admin"
    step_3 = "Login with the admin password you configured"
    step_4 = "Configure additional blocklists in Tools > Blocklists"
    step_5 = "Monitor DNS queries in Query Log"
    step_6 = "Whitelist domains if needed in Domains > Whitelist"
    dns_note = "Pi-hole is accessible to VPN clients at 10.2.0.10"
  }
}

# Troubleshooting Commands
output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting"
  value = {
    check_pods = "kubectl get pods --all-namespaces"
    check_services = "kubectl get svc --all-namespaces"
    check_pvc = "kubectl get pvc --all-namespaces"
    wireguard_logs = "kubectl logs -f deployment/wg-easy -n vpn"
    pihole_logs = "kubectl logs -f deployment/pihole -n dns"
    describe_wireguard = "kubectl describe deployment wg-easy -n vpn"
    describe_pihole = "kubectl describe deployment pihole -n dns"
    check_nodes = "kubectl get nodes -o wide"
    check_events = "kubectl get events --sort-by=.metadata.creationTimestamp"
  }
}
