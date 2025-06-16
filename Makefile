# Makefile for GKE WireGuard + Pi-hole Stack

.PHONY: help init plan apply destroy status clean validate fmt docs

# Default target
help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Check prerequisites
check-prereqs: ## Check if required tools are installed
	@echo "Checking prerequisites..."
	@which terraform >/dev/null || (echo "❌ Terraform not found" && exit 1)
	@which gcloud >/dev/null || (echo "❌ gcloud CLI not found" && exit 1)
	@which kubectl >/dev/null || (echo "❌ kubectl not found" && exit 1)
	@which helm >/dev/null || (echo "❌ helm not found" && exit 1)
	@echo "✅ All prerequisites found"

# Validate environment variables
check-env: ## Check required environment variables
	@echo "Checking environment variables..."
	@test -n "$(GOOGLE_PROJECT)" || (echo "❌ GOOGLE_PROJECT not set" && exit 1)
	@echo "✅ GOOGLE_PROJECT: $(GOOGLE_PROJECT)"
	@echo "✅ GOOGLE_REGION: $(or $(GOOGLE_REGION),us-central1)"

# Initialize Terraform
init: check-prereqs ## Initialize Terraform
	@echo "Initializing Terraform..."
	@terraform init
	@echo "✅ Terraform initialized"

# Validate Terraform configuration
validate: init ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	@terraform validate
	@echo "✅ Terraform configuration is valid"

# Format Terraform code
fmt: ## Format Terraform code
	@echo "Formatting Terraform code..."
	@terraform fmt -recursive
	@echo "✅ Code formatted"

# Plan deployment
plan: check-env validate ## Plan Terraform deployment
	@echo "Planning deployment..."
	@terraform plan \
		-var="project_id=$(GOOGLE_PROJECT)" \
		-var="region=$(or $(GOOGLE_REGION),us-central1)" \
		-out=tfplan
	@echo "✅ Plan created: tfplan"

# Apply deployment
apply: plan ## Apply Terraform deployment
	@echo "Applying deployment..."
	@terraform apply tfplan
	@echo "✅ Deployment completed"
	@$(MAKE) configure-kubectl

# Configure kubectl
configure-kubectl: ## Configure kubectl for the cluster
	@echo "Configuring kubectl..."
	@gcloud container clusters get-credentials \
		$$(terraform output -raw cluster_name) \
		--region $$(terraform output -raw cluster_location) \
		--project $(GOOGLE_PROJECT)
	@echo "✅ kubectl configured"

# Show deployment status
status: ## Show deployment status
	@echo "=== Cluster Status ==="
	@kubectl get nodes -o wide
	@echo ""
	@echo "=== Pods Status ==="
	@kubectl get pods --all-namespaces
	@echo ""
	@echo "=== Services Status ==="
	@kubectl get svc --all-namespaces

# Show service URLs
urls: ## Show service access URLs
	@echo "=== Service Access URLs ==="
	@echo "🔒 WireGuard Web UI:"
	@kubectl get svc wg-easy -n vpn -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}:51821{"\n"}' 2>/dev/null || echo "  ⏳ LoadBalancer IP pending..."
	@echo ""
	@echo "🛡️  Pi-hole Admin UI:"
	@kubectl get svc pihole-serviceTCP -n dns -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}/admin{"\n"}' 2>/dev/null || echo "  ⏳ LoadBalancer IP pending..."

# Show logs
logs-wireguard: ## Show WireGuard logs
	@kubectl logs -f deployment/wg-easy -n vpn

logs-pihole: ## Show Pi-hole logs
	@kubectl logs -f deployment/pihole -n dns

# Port forward for local access (useful during development)
port-forward-wireguard: ## Port forward WireGuard web UI to localhost:8080
	@echo "Forwarding WireGuard UI to http://localhost:8080"
	@kubectl port-forward svc/wg-easy 8080:51821 -n vpn

port-forward-pihole: ## Port forward Pi-hole admin to localhost:8081
	@echo "Forwarding Pi-hole admin to http://localhost:8081"
	@kubectl port-forward svc/pihole-serviceTCP 8081:80 -n dns

# Backup Pi-hole configuration
backup-pihole: ## Backup Pi-hole configuration
	@echo "Creating Pi-hole configuration backup..."
	@kubectl exec -n dns deployment/pihole -- tar czf /tmp/pihole-backup.tar.gz /etc/pihole /etc/dnsmasq.d
	@kubectl cp dns/$$(kubectl get pod -n dns -l app=pihole -o jsonpath='{.items[0].metadata.name}'):/tmp/pihole-backup.tar.gz ./pihole-backup-$$(date +%Y%m%d-%H%M%S).tar.gz
	@echo "✅ Backup saved to pihole-backup-$$(date +%Y%m%d-%H%M%S).tar.gz"

# Restart services
restart-wireguard: ## Restart WireGuard deployment
	@kubectl rollout restart deployment/wg-easy -n vpn
	@kubectl rollout status deployment/wg-easy -n vpn

restart-pihole: ## Restart Pi-hole deployment
	@kubectl rollout restart deployment/pihole -n dns
	@kubectl rollout status deployment/pihole -n dns

# Scale deployments
scale-up: ## Scale up deployments for high availability
	@kubectl scale deployment/wg-easy --replicas=2 -n vpn
	@kubectl scale deployment/pihole --replicas=2 -n dns
	@echo "✅ Scaled up to 2 replicas each"

scale-down: ## Scale down deployments to save costs
	@kubectl scale deployment/wg-easy --replicas=1 -n vpn
	@kubectl scale deployment/pihole --replicas=1 -n dns
	@echo "✅ Scaled down to 1 replica each"

# Security checks
security-check: ## Run basic security checks
	@echo "=== Security Check ==="
	@echo "Checking for pods running as root..."
	@kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.securityContext.runAsUser}{"\n"}{end}' | grep -E '\t(0|root|\s*$$)' || echo "✅ No pods running as root"
	@echo ""
	@echo "Checking for privileged pods..."
	@kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.privileged}{"\n"}{end}' | grep true || echo "⚠️  Some pods are privileged (expected for WireGuard)"

# Cost estimation
cost-estimate: ## Show estimated costs
	@echo "=== Monthly Cost Estimation (USD) ==="
	@echo "💰 GKE Cluster Management: Free (zonal cluster)"
	@echo "💰 Compute Instances (2x e2-micro): ~$$12-16/month"
	@echo "💰 Persistent Disks (~25GB): ~$$10/month"
	@echo "💰 LoadBalancers (2x): ~$$36/month"
	@echo "💰 Network Egress: Variable ($$0.12/GB)"
	@echo "📊 Total Estimate: ~$$60-80/month"
	@echo ""
	@echo "💡 Cost Optimization Tips:"
	@echo "  - Use preemptible instances (60-90% savings)"
	@echo "  - Consider regional persistent disks"
	@echo "  - Monitor and optimize network egress"
	@echo "  - Use committed use discounts for predictable workloads"

# Destroy everything
destroy: ## Destroy all resources
	@echo "⚠️  This will destroy ALL resources!"
	@echo "⚠️  Make sure you have backups of any important data!"
	@read -p "Type 'yes' to confirm destruction: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@terraform destroy \
		-var="project_id=$(GOOGLE_PROJECT)" \
		-var="region=$(or $(GOOGLE_REGION),us-central1)"

# Clean up local files
clean: ## Clean up local Terraform files
	@echo "Cleaning up local files..."
	@rm -rf .terraform
	@rm -f terraform.tfstate*
	@rm -f tfplan
	@rm -f *.tar.gz
	@echo "✅ Local files cleaned"

# Generate documentation
docs: ## Generate documentation
	@echo "Generating documentation..."
	@terraform-docs markdown table --output-file TERRAFORM.md .
	@echo "✅ Documentation generated: TERRAFORM.md"

# All-in-one deployment
deploy-dev: check-prereqs check-env ## Deploy everything for development
	@$(MAKE) apply
	@echo "⏳ Waiting for services to be ready..."
	@sleep 60
	@$(MAKE) urls
	@echo ""
	@echo "🎉 Development deployment completed!"
	@echo "⚠️  Don't forget to change the default passwords!"

# All-in-one production deployment
deploy-prod: check-prereqs check-env ## Deploy everything for production
	@echo "🚨 Production deployment starting..."
	@echo "Make sure you've reviewed terraform.tfvars.prod.example"
	@$(MAKE) apply
	@echo "⏳ Waiting for services to be ready..."
	@sleep 120
	@$(MAKE) urls
	@$(MAKE) security-check
	@echo ""
	@echo "🎉 Production deployment completed!"
	@echo "⚠️  CRITICAL: Change default passwords immediately!"
