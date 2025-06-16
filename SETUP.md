# Setup Guide - GKE WireGuard + Pi-hole Stack

This guide provides step-by-step instructions for setting up your self-hosted VPN with WireGuard and Pi-hole on Google Kubernetes Engine.

## Prerequisites

### 1. Install Required Tools

**macOS (using Homebrew):**
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install terraform
brew install google-cloud-sdk
brew install kubernetes-cli
brew install helm
```

**Ubuntu/Debian:**
```bash
# Update package list
sudo apt update

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Install Google Cloud CLI
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt update && sudo apt install google-cloud-cli

# Install kubectl
sudo apt install kubectl

# Install Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update && sudo apt install helm
```

### 2. Google Cloud Platform Setup

1. **Create or select a GCP project:**
   ```bash
   # List existing projects
   gcloud projects list
   
   # Create a new project (optional)
   gcloud projects create your-project-id --name="WireGuard VPN"
   
   # Set the project
   gcloud config set project your-project-id
   ```

2. **Authenticate with Google Cloud:**
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

3. **Enable billing** on your project through the [Google Cloud Console](https://console.cloud.google.com/billing)

## Quick Deployment

### Option 1: Automated Deployment (Recommended)

1. **Set environment variables:**
   ```bash
   export GOOGLE_PROJECT="your-project-id"
   export GOOGLE_REGION="us-central1"  # Choose your preferred region
   ```

2. **Run the deployment script:**
   ```bash
   ./deploy.sh
   ```

### Option 2: Manual Deployment

1. **Copy and customize configuration:**
   ```bash
   cp tf/terraform.tfvars.example tf/terraform.tfvars
   # Edit tf/terraform.tfvars with your settings
   ```

2. **Deploy using Terraform:**
   ```bash
   cd tf
   terraform init
   terraform plan -var="project_id=$GOOGLE_PROJECT" -var="region=$GOOGLE_REGION"
   terraform apply -var="project_id=$GOOGLE_PROJECT" -var="region=$GOOGLE_REGION"
   cd ..
   ```

3. **Configure kubectl:**
   ```bash
   gcloud container clusters get-credentials wireguard-cluster --region=$GOOGLE_REGION
   ```

### Option 3: Using Makefile

```bash
# Set environment variables
export GOOGLE_PROJECT="your-project-id"

# Deploy for development
make deploy-dev

# Or deploy for production
make deploy-prod
```

## Post-Deployment Configuration

### 1. Access WireGuard Web Interface

1. **Get the WireGuard service IP:**
   ```bash
   kubectl get svc wg-easy -n vpn -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. **Access the web interface:**
   - URL: `http://WIREGUARD_IP:51821`
   - Password: The password you set in `terraform.tfvars` (default: `ChangeMePlease123!`)

3. **Change the admin password immediately!**

### 2. Access Pi-hole Admin Interface

1. **Get the Pi-hole service IP:**
   ```bash
   kubectl get svc pihole-serviceTCP -n dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. **Access the admin interface:**
   - URL: `http://PIHOLE_IP/admin`
   - Password: The password you set in `terraform.tfvars` (default: `ChangeMePlease123!`)

3. **Change the admin password immediately!**

### 3. Configure WireGuard Clients

1. **Create client configurations in WireGuard web UI:**
   - Click "Add Client"
   - Give it a name (e.g., "My Phone", "My Laptop")
   - Click "Create"

2. **Download configuration or scan QR code:**
   - For mobile devices: Scan the QR code with WireGuard app
   - For computers: Download the `.conf` file

3. **Import configuration to your devices:**
   - **Android/iOS**: Use WireGuard app from app store
   - **Windows/macOS/Linux**: Use WireGuard client from [wireguard.com](https://www.wireguard.com/install/)

### 4. Configure Pi-hole

1. **Add additional blocklists:**
   - Go to "Group Management" > "Adlists"
   - Add popular blocklists:
     - `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
     - `https://someonewhocares.org/hosts/zero/hosts`
     - `https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt`

2. **Update gravity database:**
   - Go to "Tools" > "Update Gravity"
   - Click "Update"

3. **Configure whitelist if needed:**
   - Go to "Group Management" > "Domains"
   - Add any domains that should not be blocked

## Testing Your Setup

### 1. Test VPN Connection

1. **Connect with WireGuard client**
2. **Check your public IP:**
   ```bash
   curl ifconfig.me
   ```
   Should show your GKE LoadBalancer IP, not your home IP

### 2. Test DNS Blocking

1. **Test ad blocking:**
   ```bash
   nslookup doubleclick.net
   ```
   Should return `0.0.0.0` or similar blocked response

2. **Test normal DNS resolution:**
   ```bash
   nslookup google.com
   ```
   Should return normal IP addresses

### 3. Monitor Pi-hole

1. Check the Pi-hole admin dashboard for query statistics
2. Verify DNS queries are being logged
3. Check blocking effectiveness

## Security Hardening

### 1. Change Default Passwords

**Important:** Change the default passwords immediately after deployment!

```bash
# Update WireGuard password
kubectl patch secret wireguard-admin -n vpn -p '{"data":{"password":"'$(echo -n "YOUR_NEW_PASSWORD" | base64)'"}}'
kubectl rollout restart deployment/wg-easy -n vpn

# Update Pi-hole password
kubectl patch secret pihole-admin -n dns -p '{"data":{"password":"'$(echo -n "YOUR_NEW_PASSWORD" | base64)'"}}'
kubectl rollout restart deployment/pihole -n dns
```

### 2. Restrict Network Access

Edit your `tf/terraform.tfvars` to restrict access to your IP ranges:

```hcl
authorized_networks = [
  {
    cidr_block   = "YOUR.HOME.IP.ADDRESS/32"
    display_name = "Home network"
  }
]
```

Then apply the changes:
```bash
cd tf
terraform apply -var="project_id=$GOOGLE_PROJECT" -var="region=$GOOGLE_REGION"
cd ..
```

### 3. Enable Additional Security Features

For production deployments, consider:
- Enable private nodes: `enable_private_nodes = true`
- Use non-preemptible instances: `preemptible = false`
- Enable binary authorization
- Set up monitoring and alerting

## Cost Optimization

### Current Configuration Costs (USD/month estimates):

- **e2-micro instances (2x)**: ~$12-16
- **Persistent disks**: ~$10
- **LoadBalancers (2x)**: ~$36
- **Network egress**: Variable (~$0.12/GB)
- **Total**: ~$60-80/month

### Cost Reduction Tips:

1. **Use preemptible instances** (enabled by default):
   - 60-90% cost savings
   - May be interrupted (not suitable for production)

2. **Scale down when not needed:**
   ```bash
   make scale-down  # Scale to 1 replica each
   ```

3. **Use regional persistent disks** for better price/performance

4. **Monitor network egress** and optimize VPN usage

5. **Consider committed use discounts** for predictable workloads

## Monitoring and Maintenance

### 1. Check System Status

```bash
# Check overall status
make status

# Check specific services
kubectl get pods -n vpn
kubectl get pods -n dns

# Check service external IPs
make urls
```

### 2. View Logs

```bash
# WireGuard logs
make logs-wireguard

# Pi-hole logs
make logs-pihole
```

### 3. Backup Configuration

```bash
# Backup Pi-hole configuration
make backup-pihole
```

### 4. Update Services

```bash
# Restart services (pulls latest container images)
make restart-wireguard
make restart-pihole
```

### 5. Scale Services

```bash
# Scale up for high availability
make scale-up

# Scale down to save costs
make scale-down
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed troubleshooting guide.

## Cleanup

To destroy all resources and stop billing:

```bash
# Using the script
./deploy.sh destroy

# Using Makefile
make destroy

# Using Terraform directly
cd tf
terraform destroy -var="project_id=$GOOGLE_PROJECT" -var="region=$GOOGLE_REGION"
cd ..
```

**Warning:** This will permanently delete all resources and data!

## Support and Resources

- [WireGuard Documentation](https://www.wireguard.com/)
- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [Google Kubernetes Engine Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
