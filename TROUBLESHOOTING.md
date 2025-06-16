# Troubleshooting Guide - GKE WireGuard + Pi-hole Stack

This guide helps you diagnose and resolve common issues with your WireGuard + Pi-hole deployment on GKE.

## Quick Diagnostic Commands

### Check Overall System Status
```bash
# Check all pods
kubectl get pods --all-namespaces

# Check services and their external IPs
kubectl get svc --all-namespaces

# Check nodes
kubectl get nodes -o wide

# Check recent events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Common Issues and Solutions

### 1. Pods Not Starting

#### Symptoms:
- Pods stuck in `Pending`, `ContainerCreating`, or `CrashLoopBackOff` state
- Services don't get external IPs

#### Diagnosis:
```bash
# Check pod status
kubectl get pods -n vpn
kubectl get pods -n dns

# Describe problematic pods
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>
```

#### Common Causes and Solutions:

**Insufficient cluster resources:**
```bash
# Check node resources
kubectl describe nodes

# Scale up node pool if needed
kubectl scale deployment/cluster-autoscaler --replicas=1 -n kube-system

# Or manually add nodes (temporary)
gcloud container clusters resize wireguard-cluster --num-nodes=3 --region=$GOOGLE_REGION
```

**Image pull errors:**
```bash
# Check if images are accessible
docker pull ghcr.io/wg-easy/wg-easy:latest
docker pull pihole/pihole:latest

# Update deployments to use specific image tags
kubectl set image deployment/wg-easy wg-easy=ghcr.io/wg-easy/wg-easy:13 -n vpn
```

**Permission issues:**
```bash
# Check service account permissions
kubectl get serviceaccount -n vpn
kubectl get serviceaccount -n dns

# Verify RBAC permissions
kubectl auth can-i create pods --as=system:serviceaccount:vpn:default -n vpn
```

### 2. LoadBalancer Services Not Getting External IPs

#### Symptoms:
- `kubectl get svc` shows `<pending>` for EXTERNAL-IP
- Cannot access web interfaces from internet

#### Diagnosis:
```bash
# Check service status
kubectl describe svc wg-easy -n vpn
kubectl describe svc pihole-serviceTCP -n dns

# Check Google Cloud LoadBalancer status
gcloud compute forwarding-rules list
gcloud compute target-pools list
```

#### Solutions:

**Quota exceeded:**
```bash
# Check quotas
gcloud compute project-info describe --project=$GOOGLE_PROJECT

# Request quota increase in Google Cloud Console
# Go to IAM & Admin > Quotas
```

**Firewall blocking traffic:**
```bash
# Check firewall rules
gcloud compute firewall-rules list

# Ensure required ports are open
gcloud compute firewall-rules create allow-wireguard-web \
  --allow tcp:51821 \
  --source-ranges 0.0.0.0/0 \
  --description "Allow WireGuard web interface"
```

**Regional vs Zonal cluster mismatch:**
```bash
# Check cluster type
gcloud container clusters describe wireguard-cluster --region=$GOOGLE_REGION
```

### 3. WireGuard Connection Issues

#### Symptoms:
- Cannot connect to VPN
- Connected but no internet access
- DNS resolution not working

#### Diagnosis:
```bash
# Check WireGuard pod logs
kubectl logs -f deployment/wg-easy -n vpn

# Check WireGuard configuration
kubectl exec -it deployment/wg-easy -n vpn -- cat /etc/wireguard/wg0.conf

# Test from inside the pod
kubectl exec -it deployment/wg-easy -n vpn -- ping 8.8.8.8
```

#### Solutions:

**Port forwarding not working:**
```bash
# Check if port 51820 is properly exposed
kubectl get svc wg-easy -n vpn -o yaml

# Verify firewall rules
gcloud compute firewall-rules describe wireguard-cluster-wireguard-udp
```

**Kernel module issues:**
```bash
# Check if nodes support WireGuard
kubectl get nodes -o yaml | grep -A 5 -B 5 kernel

# WireGuard needs privileged access - check security context
kubectl get deployment wg-easy -n vpn -o yaml | grep -A 10 securityContext
```

**DNS configuration problems:**
```bash
# Check if Pi-hole service is accessible
kubectl exec -it deployment/wg-easy -n vpn -- nslookup pihole-dns.dns.svc.cluster.local

# Verify DNS service IP
kubectl get svc pihole-dns -n dns
```

### 4. Pi-hole Not Blocking Ads

#### Symptoms:
- Ads still showing when connected to VPN
- DNS queries not being logged in Pi-hole
- Pi-hole admin interface not accessible

#### Diagnosis:
```bash
# Check Pi-hole pod status
kubectl logs -f deployment/pihole -n dns

# Test DNS resolution
kubectl exec -it deployment/pihole -n dns -- nslookup doubleclick.net localhost

# Check Pi-hole configuration
kubectl exec -it deployment/pihole -n dns -- cat /etc/pihole/setupVars.conf
```

#### Solutions:

**DNS not configured properly in WireGuard:**
```bash
# Check WireGuard DNS setting
kubectl get configmap -n vpn -o yaml

# Verify Pi-hole service has stable ClusterIP
kubectl get svc pihole-dns -n dns
```

**Pi-hole database issues:**
```bash
# Update gravity database
kubectl exec -it deployment/pihole -n dns -- pihole -g

# Check blocklist status
kubectl exec -it deployment/pihole -n dns -- pihole -b -l
```

**Storage issues:**
```bash
# Check persistent volume
kubectl get pv
kubectl get pvc -n dns

# Verify Pi-hole data persistence
kubectl exec -it deployment/pihole -n dns -- ls -la /etc/pihole/
```

### 5. High Costs / Unexpected Charges

#### Diagnosis:
```bash
# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# List all Google Cloud resources
gcloud compute instances list
gcloud compute disks list
gcloud compute forwarding-rules list
```

#### Solutions:

**Scale down when not needed:**
```bash
# Scale deployments to 1 replica
kubectl scale deployment/wg-easy --replicas=1 -n vpn
kubectl scale deployment/pihole --replicas=1 -n dns

# Use preemptible instances (edit terraform.tfvars)
preemptible = true
```

**Optimize storage:**
```bash
# Check disk usage
kubectl exec -it deployment/pihole -n dns -- df -h

# Reduce PVC size if possible (requires data migration)
```

**Monitor egress traffic:**
```bash
# Check network usage in Google Cloud Console
# Set up billing alerts for unexpected charges
```

### 6. SSL/TLS and Security Issues

#### Symptoms:
- Browser security warnings
- Cannot access web interfaces over HTTPS
- Security scanners reporting vulnerabilities

#### Solutions:

**Add HTTPS to web interfaces:**
```bash
# Install cert-manager for automatic SSL certificates
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create certificate issuers and ingress resources
# (This requires additional configuration - see advanced setup)
```

**Restrict access by source IP:**
```bash
# Edit service annotations
kubectl annotate svc wg-easy -n vpn cloud.google.com/load-balancer-source-ranges="YOUR.IP.ADDRESS/32"
kubectl annotate svc pihole-serviceTCP -n dns cloud.google.com/load-balancer-source-ranges="YOUR.IP.ADDRESS/32"
```

**Enable network policies:**
```bash
# Verify network policies are active
kubectl get networkpolicy --all-namespaces

# Check Calico status (if using network policies)
kubectl get pods -n kube-system | grep calico
```

## Performance Issues

### 1. Slow VPN Connection

#### Diagnosis:
```bash
# Test speed without VPN
curl -o /dev/null -s -w "Download: %{speed_download} bytes/sec\n" http://speedtest.tele2.net/100MB.zip

# Test speed with VPN connected
# Run same command from device connected to VPN
```

#### Solutions:

**Upgrade node machine type:**
```hcl
# In terraform.tfvars
machine_type = "e2-standard-2"  # Upgrade from e2-micro
```

**Use SSD persistent disks:**
```hcl
# In terraform.tfvars
disk_type = "pd-ssd"  # Upgrade from pd-standard
```

**Optimize WireGuard settings:**
```bash
kubectl edit configmap wg-easy-config -n vpn
# Adjust MTU, keepalive settings
```

### 2. High Memory/CPU Usage

#### Diagnosis:
```bash
# Check resource usage
kubectl top pods -n vpn
kubectl top pods -n dns

# Check resource limits
kubectl describe deployment wg-easy -n vpn
kubectl describe deployment pihole -n dns
```

#### Solutions:

**Increase resource limits:**
```bash
kubectl patch deployment wg-easy -n vpn -p '{"spec":{"template":{"spec":{"containers":[{"name":"wg-easy","resources":{"limits":{"memory":"1Gi","cpu":"1000m"}}}]}}}}'

kubectl patch deployment pihole -n dns -p '{"spec":{"template":{"spec":{"containers":[{"name":"pihole","resources":{"limits":{"memory":"1Gi","cpu":"1000m"}}}]}}}}'
```

**Scale horizontally:**
```bash
kubectl scale deployment/wg-easy --replicas=2 -n vpn
kubectl scale deployment/pihole --replicas=2 -n dns
```

## Advanced Troubleshooting

### 1. Network Debugging

```bash
# Test connectivity between pods
kubectl run debug --image=nicolaka/netshoot --rm -it -- /bin/bash

# Inside the debug pod:
# Test DNS resolution
nslookup pihole-dns.dns.svc.cluster.local

# Test connectivity to services
nc -zv pihole-dns.dns.svc.cluster.local 53
nc -zv wg-easy.vpn.svc.cluster.local 51821

# Check iptables rules (on nodes)
kubectl get pods -o wide
gcloud compute ssh <node-name> --zone=<zone>
sudo iptables -L -n
```

### 2. Storage Debugging

```bash
# Check storage classes
kubectl get storageclass

# Check persistent volumes
kubectl get pv -o wide

# Check volume mounts
kubectl exec -it deployment/pihole -n dns -- mount | grep pihole
```

### 3. RBAC and Permissions

```bash
# Check current permissions
kubectl auth can-i '*' '*' --all-namespaces

# Test specific service account permissions
kubectl auth can-i create pods --as=system:serviceaccount:vpn:default

# Check cluster roles and bindings
kubectl get clusterroles | grep -i helm
kubectl get clusterrolebindings | grep -i helm
```

## Getting Help

### 1. Collect Diagnostic Information

Run this script to collect comprehensive diagnostic info:

```bash
#!/bin/bash
echo "=== GKE Cluster Info ==="
kubectl cluster-info

echo "=== Nodes ==="
kubectl get nodes -o wide

echo "=== All Pods ==="
kubectl get pods --all-namespaces -o wide

echo "=== Services ==="
kubectl get svc --all-namespaces

echo "=== PVCs ==="
kubectl get pvc --all-namespaces

echo "=== Events (Recent) ==="
kubectl get events --sort-by=.metadata.creationTimestamp --all-namespaces | tail -20

echo "=== WireGuard Logs ==="
kubectl logs deployment/wg-easy -n vpn --tail=50

echo "=== Pi-hole Logs ==="
kubectl logs deployment/pihole -n dns --tail=50
```

### 2. Community Resources

- **WireGuard Community**: [Reddit r/WireGuard](https://reddit.com/r/WireGuard)
- **Pi-hole Community**: [Pi-hole Discourse](https://discourse.pi-hole.net/)
- **GKE Documentation**: [Google Cloud Kubernetes Engine](https://cloud.google.com/kubernetes-engine/docs)
- **Terraform Google Provider**: [HashiCorp Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### 3. Professional Support

For production deployments, consider:
- Google Cloud Support plans
- Certified Kubernetes administrators
- Professional services for custom configurations

## Prevention

### 1. Regular Maintenance

```bash
# Weekly checks
make status
make security-check

# Monthly tasks
make backup-pihole
kubectl get pods --all-namespaces | grep -v Running
gcloud compute project-info describe --project=$GOOGLE_PROJECT | grep quotas
```

### 2. Monitoring Setup

Consider setting up monitoring with:
- Google Cloud Monitoring
- Prometheus + Grafana
- Custom alerting for service availability
- Cost monitoring and alerts

### 3. Documentation

Keep track of:
- Configuration changes
- Client devices and configurations
- Backup schedules
- Cost tracking and optimization efforts
