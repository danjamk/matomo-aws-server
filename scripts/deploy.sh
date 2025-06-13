#!/bin/bash

# Matomo AWS Server Deployment Script
# This script deploys Matomo stacks to AWS (run setup.sh first for initial setup)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if setup has been completed
check_setup() {
    log_info "Checking setup status..."
    
    # Check if virtual environment exists
    if [ ! -d "venv" ]; then
        log_error "Virtual environment not found. Please run ./scripts/setup.sh first."
        exit 1
    fi
    
    # Check if CDK is available
    if ! command -v cdk &> /dev/null; then
        log_error "CDK not found. Please run ./scripts/setup.sh first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run ./scripts/setup.sh first."
        exit 1
    fi
    
    log_success "Setup verified"
}

# Deploy the stacks
deploy_stacks() {
    log_info "Starting deployment..."
    
    # Ensure virtual environment is activated
    if [[ "$VIRTUAL_ENV" == "" ]]; then
        log_info "Activating virtual environment..."
        source venv/bin/activate
    fi
    
    # Verify we have CDK available
    if ! command -v cdk &> /dev/null; then
        log_error "CDK not found. Please install with: npm install -g aws-cdk"
        exit 1
    fi
    
    # Deploy all stacks
    log_info "Deploying Matomo infrastructure..."
    cdk deploy --all --require-approval never
    
    log_success "Deployment completed!"
}

# Display deployment information
show_deployment_info() {
    log_info "Retrieving deployment information..."
    
    # Ensure we're using the virtual environment python
    local python_cmd="python"
    if [[ "$VIRTUAL_ENV" != "" ]]; then
        python_cmd="python"
    elif command -v python3 &> /dev/null; then
        python_cmd="python3"
    fi
    
    local project_name=$($python_cmd -c "import json; print(json.load(open('cdk.json'))['context']['matomo']['projectName'])")
    local enable_database=$($python_cmd -c "import json; print(json.load(open('cdk.json'))['context']['matomo']['enableDatabase'])")
    
    echo ""
    echo "=================================================="
    echo "         MATOMO DEPLOYMENT COMPLETED"
    echo "=================================================="
    echo ""
    
    # Get stack outputs
    local compute_stack="${project_name}-compute"
    
    if aws cloudformation describe-stacks --stack-name "$compute_stack" &> /dev/null; then
        local matomo_url=$(aws cloudformation describe-stacks --stack-name "$compute_stack" --query "Stacks[0].Outputs[?OutputKey=='MatomoUrl'].OutputValue" --output text)
        local public_ip=$(aws cloudformation describe-stacks --stack-name "$compute_stack" --query "Stacks[0].Outputs[?OutputKey=='PublicIp'].OutputValue" --output text)
        local ssh_command=$(aws cloudformation describe-stacks --stack-name "$compute_stack" --query "Stacks[0].Outputs[?OutputKey=='SshCommand'].OutputValue" --output text)
        
        echo "🌐 Matomo URL: $matomo_url"
        echo "🖥️  Public IP: $public_ip"
        echo ""
        echo "🔐 SSH Access:"
        echo "   $ssh_command"
        echo ""
        
        if [ "$enable_database" = "True" ]; then
            local database_stack="${project_name}-database"
            if aws cloudformation describe-stacks --stack-name "$database_stack" &> /dev/null; then
                local db_endpoint=$(aws cloudformation describe-stacks --stack-name "$database_stack" --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" --output text)
                echo "🗄️  Database: RDS MySQL at $db_endpoint"
                echo "   Credentials stored in AWS Secrets Manager"
                echo "   Get password: ./scripts/get-db-password.sh"
            fi
        else
            echo "🗄️  Database: RDS MySQL deployment not enabled"
        fi
        
        echo ""
        echo "📋 Next Steps:"
        echo "   1. Wait 10-15 minutes for Matomo installation to complete"
        echo "   2. Access Matomo at: $matomo_url"
        echo "   3. Complete the web-based setup wizard"
        echo "   4. Configure DNS and SSL for production use"
        echo ""
        echo "🛠️  Useful Scripts:"
        echo "   🔐 Get DB password: ./scripts/get-db-password.sh"
        echo "   📊 View all info:   ./scripts/get-info.sh"
        echo "   🧹 Clean up:        ./scripts/destroy.sh"
        echo ""
        echo "⚠️  IMPORTANT: Production Setup Required"
        echo "   🌍 Configure DNS: Point your domain to $public_ip"
        echo "   🔒 Setup SSL: Install Let's Encrypt or use ACM"
        echo "   📖 See README.md for detailed DNS and SSL instructions"
        
    else
        log_error "Could not retrieve deployment information"
    fi
}

# Main execution
main() {
    echo ""
    echo "🚀 Matomo AWS Server Deployment"
    echo "================================"
    echo ""
    
    check_setup
    deploy_stacks
    show_deployment_info
    
    echo ""
    log_success "Deployment completed!"
}

# Run main function
main "$@"