# GKE WireGuard + Pi-hole Stack

This repository contains Terraform code to deploy a self-hosted VPN solution using WireGuard (via wg-easy) and Pi-hole DNS adblocker on Google Kubernetes Engine (GKE).

## Architecture

- **GKE Cluster**: Cost-optimized cluster with e2-micro instances
- **WireGuard**: Deployed via wg-easy for easy client management
- **Pi-hole**: DNS adblocker with persistent storage
- **Networking**: Proper firewall rules and service exposure
- **Security**: Least privilege IAM and secure admin access

## Project Structure

```
├── tf/                          # Terraform configuration files
│   ├── providers.tf            # Provider configurations
│   ├── variables.tf            # Variable definitions
│   ├── gke.tf                  # GKE cluster configuration
│   ├── kubernetes.tf           # Kubernetes resources
│   ├── wireguard.tf           # WireGuard deployment
│   ├── pihole.tf              # Pi-hole deployment
│   ├── outputs.tf             # Output definitions
│   └── terraform.tfvars.example # Example configuration
├── deploy.sh                   # Automated deployment script
├── Makefile                   # Management commands
└── docs/                      # Documentation files
```

## Prerequisites

1. Google Cloud Platform account with billing enabled
2. `gcloud` CLI installed and authenticated
3. Terraform >= 1.0 installed
4. `kubectl` installed for cluster management
5. `helm` CLI installed (optional, for manual operations)

## Cost Optimization

This setup uses:
- **e2-micro instances**: ~$6-8/month per node
- **Preemptible nodes**: 60-90% cost savings
- **Regional persistent disks**: Cost-effective storage
- **Minimal node count**: 1-2 nodes for redundancy

## Quick Start

1. Clone this repository
2. Set up your GCP project:
   ```bash
   export GOOGLE_PROJECT="your-project-id"
   export GOOGLE_REGION="us-central1"
   ```

3. Initialize and apply Terraform:
   ```bash
   cd tf
   terraform init
   terraform plan -var="project_id=${GOOGLE_PROJECT}" -var="region=${GOOGLE_REGION}"
   terraform apply -var="project_id=${GOOGLE_PROJECT}" -var="region=${GOOGLE_REGION}"
   cd ..
   ```

4. Configure kubectl:
   ```bash
   gcloud container clusters get-credentials wireguard-cluster --region=${GOOGLE_REGION}
   ```

5. Access services:
   - WireGuard UI: `kubectl get svc wg-easy -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
   - Pi-hole Admin: `kubectl get svc pihole-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`

## Configuration

### WireGuard Clients

1. Access the wg-easy web UI using the LoadBalancer IP
2. Create client configurations
3. Download and import configs to your WireGuard clients

### Pi-hole Setup

1. Access Pi-hole admin interface
2. Configure blocklists and whitelist domains as needed
3. Note the Pi-hole service IP for DNS configuration

## Security Considerations

- Change default passwords immediately
- Restrict LoadBalancer source IP ranges
- Enable GKE Workload Identity
- Use Google Cloud Armor for additional protection
- Regularly update container images

## Monitoring and Maintenance

- Monitor GKE cluster health in Google Cloud Console
- Check Pi-hole logs for DNS blocking effectiveness
- Update WireGuard client configurations as needed
- Scale nodes based on usage patterns

## Cleanup

```bash
cd tf
terraform destroy -var="project_id=${GOOGLE_PROJECT}" -var="region=${GOOGLE_REGION}"
cd ..
```

## Support

For issues and questions, check the following:
- [wg-easy documentation](https://github.com/wg-easy/wg-easy)
- [Pi-hole documentation](https://docs.pi-hole.net/)
- [GKE documentation](https://cloud.google.com/kubernetes-engine/docs)
