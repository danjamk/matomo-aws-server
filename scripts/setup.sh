#!/bin/bash

# Matomo AWS Server Setup Script
# This script handles one-time setup: prerequisites, credentials, dependencies, and CDK bootstrap

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

# Check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v cdk &> /dev/null; then
        log_error "AWS CDK is not installed. Please install it first: npm install -g aws-cdk"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    log_success "All prerequisites are installed"
}

# Check AWS credentials
check_aws_credentials() {
    log_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region || echo "us-east-1")
    
    log_success "AWS credentials configured"
    log_info "Account ID: $account_id"
    log_info "Region: $region"
}

# Install Python dependencies
install_dependencies() {
    log_info "Installing Python dependencies..."
    
    # Check if venv exists and is properly set up
    if [ ! -d "venv" ]; then
        log_info "Creating virtual environment..."
        # Try python first (if user has it), then python3
        if command -v python &> /dev/null; then
            python -m venv venv
        else
            python3 -m venv venv
        fi
    fi
    
    # Activate virtual environment
    log_info "Activating virtual environment..."
    source venv/bin/activate
    
    # Verify we're in the virtual environment
    if [[ "$VIRTUAL_ENV" == "" ]]; then
        log_error "Failed to activate virtual environment"
        exit 1
    fi
    
    # Upgrade pip and install dependencies
    pip install --upgrade pip
    pip install -r requirements.txt
    
    log_success "Dependencies installed in virtual environment: $VIRTUAL_ENV"
}

# Bootstrap CDK if needed
bootstrap_cdk() {
    log_info "Checking CDK bootstrap status..."
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region || echo "us-east-1")
    
    # Check if CDK is already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region $region &> /dev/null; then
        log_info "CDK already bootstrapped in $region"
    else
        log_info "Bootstrapping CDK in $region..."
        cdk bootstrap aws://$account_id/$region
        log_success "CDK bootstrapped"
    fi
}

# Main execution
main() {
    echo ""
    echo "🛠️  Matomo AWS Server Setup"
    echo "============================"
    echo ""
    
    check_prerequisites
    check_aws_credentials
    install_dependencies
    bootstrap_cdk
    
    echo ""
    log_success "Setup completed! You can now run ./scripts/deploy.sh to deploy Matomo."
    echo ""
    echo "📋 Next Steps:"
    echo "   1. Run: ./scripts/deploy.sh"
    echo "   2. Wait for deployment to complete"
    echo "   3. Access Matomo via the provided URL"
    echo ""
}

# Run main function
main "$@"