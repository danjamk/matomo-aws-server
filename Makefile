# Matomo AWS Server Makefile
# Convenient wrapper for all deployment and management scripts

.PHONY: help setup deploy info password validate validate-all clean clean-force status diff logs ssh

# Default target
help: ## Show this help message
	@echo ""
	@echo "🚀 Matomo AWS Server - Available Commands"
	@echo "========================================"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "📋 Common Workflows:"
	@echo "  make setup deploy validate    # Complete deployment"
	@echo "  make status                   # Check current status"
	@echo "  make clean                    # Interactive cleanup"
	@echo "  make clean-force              # Automated cleanup"
	@echo ""

# === SETUP AND DEPLOYMENT ===

setup: ## Run one-time setup (prerequisites, dependencies, CDK bootstrap)
	@echo "🛠️  Running initial setup..."
	./scripts/setup.sh

deploy: ## Deploy Matomo infrastructure to AWS
	@echo "🚀 Deploying to AWS..."
	./scripts/deploy.sh

# === INFORMATION AND STATUS ===

info: ## Get all deployment information (IP, SSH, database details)
	@echo "📊 Retrieving deployment information..."
	./scripts/get-info.sh

password: ## Get database username and password
	@echo "🔐 Retrieving database credentials..."
	./scripts/get-db-password.sh

status: info ## Alias for info command

# === VALIDATION ===

validate-infrastructure: ## Validate AWS infrastructure (VPC, EC2, RDS, security groups)
	@echo "✅ Validating infrastructure..."
	./scripts/validate-infrastructure.sh

validate-matomo: ## Validate Matomo installation (single check)
	@echo "✅ Validating Matomo installation..."
	./scripts/validate-matomo.sh

validate-matomo-wait: ## Wait for Matomo installation to complete (15 min timeout)
	@echo "⏳ Waiting for Matomo installation to complete..."
	./scripts/validate-matomo.sh --wait

validate-matomo-wait-30: ## Wait for Matomo installation with 30 minute timeout
	@echo "⏳ Waiting for Matomo installation (30 min timeout)..."
	./scripts/validate-matomo.sh --wait --timeout 1800

validate: validate-infrastructure validate-matomo ## Run all validation checks

validate-all: validate-infrastructure validate-matomo-wait ## Run all validation checks with wait mode

# === CLEANUP ===

clean: ## Remove all AWS resources (interactive with confirmation)
	@echo "🧹 Starting interactive cleanup..."
	./scripts/destroy.sh

clean-force: ## Remove all AWS resources (no prompts, for automation)
	@echo "🧹 Starting automated cleanup..."
	./scripts/destroy.sh --force

destroy: clean ## Alias for clean command

destroy-force: clean-force ## Alias for clean-force command

# === ADVANCED TARGETS ===

ssh: ## Connect to EC2 instance via SSH (requires deployment info)
	@echo "🔗 Connecting to EC2 instance..."
	@echo "First retrieving SSH key and connection details..."
	@./scripts/get-info.sh > /dev/null 2>&1 || (echo "❌ Failed to get deployment info. Is the infrastructure deployed?" && exit 1)
	@if [ -f matomo-key.pem ]; then \
		PUBLIC_IP=$$(./scripts/get-info.sh 2>/dev/null | grep "Public IP:" | cut -d' ' -f3); \
		if [ -n "$$PUBLIC_IP" ] && [ "$$PUBLIC_IP" != "N/A" ]; then \
			echo "🔗 Connecting to $$PUBLIC_IP..."; \
			ssh -i matomo-key.pem ec2-user@$$PUBLIC_IP; \
		else \
			echo "❌ Could not determine public IP address"; \
			exit 1; \
		fi; \
	else \
		echo "❌ SSH key file not found. Run 'make info' first."; \
		exit 1; \
	fi

logs: ## View Matomo installation logs via SSH
	@echo "📋 Viewing installation logs..."
	@./scripts/get-info.sh > /dev/null 2>&1 || (echo "❌ Failed to get deployment info. Is the infrastructure deployed?" && exit 1)
	@if [ -f matomo-key.pem ]; then \
		PUBLIC_IP=$$(./scripts/get-info.sh 2>/dev/null | grep "Public IP:" | cut -d' ' -f3); \
		if [ -n "$$PUBLIC_IP" ] && [ "$$PUBLIC_IP" != "N/A" ]; then \
			echo "📋 Connecting to $$PUBLIC_IP to view logs..."; \
			ssh -i matomo-key.pem ec2-user@$$PUBLIC_IP 'sudo tail -f /var/log/matomo-install.log'; \
		else \
			echo "❌ Could not determine public IP address"; \
			exit 1; \
		fi; \
	else \
		echo "❌ SSH key file not found. Run 'make info' first."; \
		exit 1; \
	fi

diff: ## Preview changes before deployment
	@echo "🔍 Previewing deployment changes..."
	@if [ -d "venv" ]; then \
		source venv/bin/activate && cdk diff; \
	elif [ -d ".venv" ]; then \
		source .venv/bin/activate && cdk diff; \
	else \
		cdk diff; \
	fi

# === WORKFLOW TARGETS ===

fresh-deploy: setup deploy validate-all ## Complete fresh deployment with validation
	@echo ""
	@echo "🎉 Fresh deployment completed!"
	@echo "Your Matomo instance should be ready at the URL shown above."

quick-deploy: deploy validate ## Quick deployment and validation (assumes setup already done)
	@echo ""
	@echo "⚡ Quick deployment completed!"

redeploy: deploy validate-matomo ## Redeploy and validate Matomo (skip infrastructure validation)
	@echo ""
	@echo "🔄 Redeployment completed!"

check: validate ## Run all validation checks (alias)

health: validate-infrastructure validate-matomo ## Basic health check (infrastructure + Matomo)

# === UTILITY TARGETS ===

open: ## Open Matomo URL in default browser (macOS/Linux)
	@echo "🌐 Opening Matomo in browser..."
	@MATOMO_URL=$$(./scripts/get-info.sh 2>/dev/null | grep "Matomo URL:" | cut -d' ' -f3); \
	if [ -n "$$MATOMO_URL" ] && [ "$$MATOMO_URL" != "N/A" ]; then \
		if command -v open >/dev/null 2>&1; then \
			open "$$MATOMO_URL"; \
		elif command -v xdg-open >/dev/null 2>&1; then \
			xdg-open "$$MATOMO_URL"; \
		else \
			echo "Please open this URL manually: $$MATOMO_URL"; \
		fi; \
	else \
		echo "❌ Could not determine Matomo URL. Is the infrastructure deployed?"; \
		exit 1; \
	fi

version: ## Show version information
	@echo "🔧 Tool Versions:"
	@echo "=================="
	@echo -n "AWS CLI:     "; aws --version 2>/dev/null || echo "Not installed"
	@echo -n "AWS CDK:     "; cdk --version 2>/dev/null || echo "Not installed"
	@echo -n "Python:      "; python3 --version 2>/dev/null || echo "Not installed"
	@echo -n "Git:         "; git --version 2>/dev/null || echo "Not installed"
	@echo ""
	@echo -n "AWS Account: "; aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "Not configured"
	@echo -n "AWS Region:  "; aws configure get region 2>/dev/null || echo "Not configured"

clean-local: ## Clean up local files (SSH keys, CDK output, etc.)
	@echo "🧹 Cleaning up local files..."
	@rm -f matomo-key.pem
	@rm -rf cdk.out
	@rm -rf venv .venv
	@echo "✅ Local cleanup completed"

# === HELP TARGETS ===

examples: ## Show common usage examples
	@echo ""
	@echo "📚 Common Usage Examples"
	@echo "======================="
	@echo ""
	@echo "🚀 First-time deployment:"
	@echo "  make fresh-deploy"
	@echo ""
	@echo "⚡ Quick deployment (after initial setup):"
	@echo "  make quick-deploy"
	@echo ""
	@echo "🔄 Redeploy after code changes:"
	@echo "  make redeploy"
	@echo ""
	@echo "✅ Check if everything is working:"
	@echo "  make check"
	@echo ""
	@echo "📊 Get deployment information:"
	@echo "  make info"
	@echo ""
	@echo "🔗 Connect to server:"
	@echo "  make ssh"
	@echo ""
	@echo "📋 View installation logs:"
	@echo "  make logs"
	@echo ""
	@echo "🧹 Clean up everything:"
	@echo "  make clean              # Interactive"
	@echo "  make clean-force        # Automated"
	@echo ""

scripts: ## Show available script files
	@echo ""
	@echo "📁 Available Scripts"
	@echo "==================="
	@echo ""
	@ls -la scripts/
	@echo ""
	@echo "💡 All scripts can be run directly or via make targets"

# Make sure scripts are executable
$(shell find scripts -name "*.sh" -exec chmod +x {} \;)