#!/bin/bash

# Deployment script for GKE WireGuard + Pi-hole Stack
# This script automates the deployment process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    command -v terraform >/dev/null 2>&1 || { print_error "Terraform is required but not installed. Aborting."; exit 1; }
    command -v gcloud >/dev/null 2>&1 || { print_error "gcloud CLI is required but not installed. Aborting."; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed. Aborting."; exit 1; }
    
    print_success "All prerequisites are installed"
}

# Check if user is authenticated with gcloud
check_gcloud_auth() {
    print_status "Checking gcloud authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    print_success "gcloud authentication verified"
}

# Validate required environment variables
check_environment() {
    print_status "Checking environment variables..."
    
    if [ -z "$GOOGLE_PROJECT" ]; then
        print_error "GOOGLE_PROJECT environment variable is not set"
        print_status "Please set it with: export GOOGLE_PROJECT=your-project-id"
        exit 1
    fi
    
    if [ -z "$GOOGLE_REGION" ]; then
        print_warning "GOOGLE_REGION not set, using default: us-central1"
        export GOOGLE_REGION="us-central1"
    fi
    
    print_success "Environment variables validated"
    print_status "Project: $GOOGLE_PROJECT"
    print_status "Region: $GOOGLE_REGION"
}

# Enable required GCP APIs
enable_apis() {
    print_status "Enabling required Google Cloud APIs..."
    
    apis=(
        "compute.googleapis.com"
        "container.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
        "serviceusage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        print_status "Enabling $api..."
        gcloud services enable "$api" --project="$GOOGLE_PROJECT"
    done
    
    print_success "APIs enabled successfully"
}

# Initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    terraform init
    print_success "Terraform initialized"
}

# Plan Terraform deployment
plan_terraform() {
    print_status "Planning Terraform deployment..."
    terraform plan \
        -var="project_id=$GOOGLE_PROJECT" \
        -var="region=$GOOGLE_REGION" \
        -out=tfplan
    
    print_success "Terraform plan created"
    print_warning "Review the plan above before continuing"
}

# Apply Terraform configuration
apply_terraform() {
    print_status "Applying Terraform configuration..."
    terraform apply tfplan
    print_success "Terraform deployment completed"
}

# Configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."
    
    cluster_name=$(terraform output -raw cluster_name)
    cluster_location=$(terraform output -raw cluster_location)
    
    gcloud container clusters get-credentials "$cluster_name" \
        --region "$cluster_location" \
        --project "$GOOGLE_PROJECT"
    
    print_success "kubectl configured for cluster: $cluster_name"
}

# Wait for services to be ready
wait_for_services() {
    print_status "Waiting for services to get external IPs..."
    
    print_status "Waiting for WireGuard service..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wg-easy -n vpn --timeout=300s
    
    print_status "Waiting for Pi-hole service..."
    kubectl wait --for=condition=ready pod -l app=pihole -n dns --timeout=300s
    
    print_success "Services are ready"
}

# Display access information
show_access_info() {
    print_success "Deployment completed successfully!"
    echo
    print_status "=== Access Information ==="
    
    # Get service IPs
    print_status "Getting service external IPs (this may take a few minutes)..."
    
    # Wait for LoadBalancer IPs
    print_status "Waiting for WireGuard LoadBalancer IP..."
    wg_ip=""
    while [ -z "$wg_ip" ]; do
        wg_ip=$(kubectl get svc wg-easy -n vpn -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -z "$wg_ip" ]; then
            sleep 10
            print_status "Still waiting for WireGuard IP..."
        fi
    done
    
    print_status "Waiting for Pi-hole LoadBalancer IP..."
    pihole_ip=""
    while [ -z "$pihole_ip" ]; do
        pihole_ip=$(kubectl get svc pihole-serviceTCP -n dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -z "$pihole_ip" ]; then
            sleep 10
            print_status "Still waiting for Pi-hole IP..."
        fi
    done
    
    echo
    print_success "🔒 WireGuard Web UI: http://$wg_ip:51821"
    print_success "🛡️  Pi-hole Admin UI: http://$pihole_ip/admin"
    echo
    print_warning "⚠️  IMPORTANT SECURITY NOTES:"
    print_warning "1. Change the default admin passwords immediately!"
    print_warning "2. Consider restricting LoadBalancer source IP ranges"
    print_warning "3. Enable firewall rules for your specific IP ranges"
    echo
    print_status "=== Next Steps ==="
    print_status "1. Access WireGuard UI and create client configurations"
    print_status "2. Configure Pi-hole blocklists and settings"
    print_status "3. Test VPN connectivity and DNS blocking"
    print_status "4. Monitor costs in Google Cloud Console"
    echo
}

# Main deployment function
main() {
    print_status "Starting GKE WireGuard + Pi-hole deployment..."
    echo
    
    check_prerequisites
    check_gcloud_auth
    check_environment
    enable_apis
    init_terraform
    plan_terraform
    
    # Ask for confirmation
    echo
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled"
        exit 0
    fi
    
    apply_terraform
    configure_kubectl
    wait_for_services
    show_access_info
}

# Handle script arguments
case "${1:-}" in
    "plan")
        check_prerequisites
        check_gcloud_auth
        check_environment
        init_terraform
        plan_terraform
        ;;
    "apply")
        check_prerequisites
        check_gcloud_auth
        check_environment
        apply_terraform
        configure_kubectl
        wait_for_services
        show_access_info
        ;;
    "destroy")
        print_warning "This will destroy all resources. Are you sure?"
        read -p "Type 'yes' to confirm: " -r
        if [[ $REPLY == "yes" ]]; then
            terraform destroy \
                -var="project_id=$GOOGLE_PROJECT" \
                -var="region=$GOOGLE_REGION"
        else
            print_status "Destroy cancelled"
        fi
        ;;
    "status")
        kubectl get pods --all-namespaces
        kubectl get svc --all-namespaces
        ;;
    *)
        main
        ;;
esac
