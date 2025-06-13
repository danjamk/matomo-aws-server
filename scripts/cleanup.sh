#!/bin/bash

# Matomo AWS Server Cleanup Script
# This script completely removes all AWS resources created by the Matomo deployment

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
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v cdk &> /dev/null; then
        log_error "AWS CDK is not installed. Please install it first: npm install -g aws-cdk"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
}

# Get project configuration
get_project_config() {
    if [ ! -f "cdk.json" ]; then
        log_error "cdk.json not found. Are you in the project root directory?"
        exit 1
    fi
    
    # Use python if available (from venv), otherwise python3
    local python_cmd="python3"
    if command -v python &> /dev/null; then
        python_cmd="python"
    fi
    
    PROJECT_NAME=$($python_cmd -c "import json; print(json.load(open('cdk.json'))['context']['matomo']['projectName'])" 2>/dev/null || echo "matomo-analytics")
    ENABLE_DATABASE=$($python_cmd -c "import json; print(json.load(open('cdk.json'))['context']['matomo']['enableDatabase'])" 2>/dev/null || echo "false")
}

# Check if stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" &> /dev/null
}

# Display what will be deleted
show_deletion_plan() {
    echo ""
    echo "=================================================="
    echo "         MATOMO CLEANUP PLAN"
    echo "=================================================="
    echo ""
    echo "The following AWS resources will be PERMANENTLY DELETED:"
    echo ""
    
    local networking_stack="${PROJECT_NAME}-networking"
    local database_stack="${PROJECT_NAME}-database"
    local compute_stack="${PROJECT_NAME}-compute"
    
    if stack_exists "$compute_stack"; then
        echo "🖥️  Compute Stack ($compute_stack):"
        echo "   - EC2 Instance"
        echo "   - IAM Role and Policies"
        echo "   - SSH Key Pair"
        echo "   - Parameter Store entries"
        echo ""
    fi
    
    if stack_exists "$database_stack"; then
        echo "🗄️  Database Stack ($database_stack):"
        echo "   - RDS MySQL Instance"
        echo "   - Database Subnet Group"
        echo "   - Secrets Manager Secret"
        echo "   - All database data (PERMANENT LOSS)"
        echo ""
    fi
    
    if stack_exists "$networking_stack"; then
        echo "🌐 Networking Stack ($networking_stack):"
        echo "   - VPC and Subnets"
        echo "   - Internet Gateway"
        echo "   - NAT Gateway"
        echo "   - Security Groups"
        echo "   - Route Tables"
        echo ""
    fi
    
    echo "💰 This will stop all ongoing AWS charges for these resources."
    echo ""
    echo -e "${RED}⚠️  WARNING: This action cannot be undone!${NC}"
    echo -e "${RED}⚠️  All data will be permanently lost!${NC}"
    echo ""
}

# Confirm deletion
confirm_deletion() {
    echo -e "${YELLOW}Are you sure you want to delete all Matomo resources?${NC}"
    echo "Type 'DELETE' to confirm (case sensitive): "
    read -r confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_warning "Proceeding with cleanup in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove SSH key file if it exists
    if [ -f "matomo-key.pem" ]; then
        rm -f matomo-key.pem
        log_info "Removed local SSH key file"
    fi
    
    # Remove virtual environment if it exists
    if [ -d "venv" ]; then
        rm -rf venv
        log_info "Removed Python virtual environment"
    fi
    
    # Remove CDK output directory
    if [ -d "cdk.out" ]; then
        rm -rf cdk.out
        log_info "Removed CDK output directory"
    fi
}

# Destroy CDK stacks
destroy_stacks() {
    log_info "Destroying CDK stacks..."
    
    # Activate virtual environment if it exists
    if [ -d "venv" ]; then
        source venv/bin/activate
    fi
    
    # Destroy all stacks
    log_info "Destroying all Matomo stacks..."
    if cdk destroy --all --force; then
        log_success "All CDK stacks destroyed successfully"
    else
        log_error "Failed to destroy some CDK stacks"
        log_info "You may need to manually clean up remaining resources in the AWS Console"
        return 1
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local networking_stack="${PROJECT_NAME}-networking"
    local database_stack="${PROJECT_NAME}-database"
    local compute_stack="${PROJECT_NAME}-compute"
    local all_clean=true
    
    # Check if stacks still exist
    if stack_exists "$compute_stack"; then
        log_warning "Compute stack still exists: $compute_stack"
        all_clean=false
    fi
    
    if stack_exists "$database_stack"; then
        log_warning "Database stack still exists: $database_stack"
        all_clean=false
    fi
    
    if stack_exists "$networking_stack"; then
        log_warning "Networking stack still exists: $networking_stack"
        all_clean=false
    fi
    
    if [ "$all_clean" = true ]; then
        log_success "All stacks have been successfully removed"
        return 0
    else
        log_warning "Some resources may still exist. Check the AWS Console for any remaining resources."
        return 1
    fi
}

# Show cleanup completion message
show_completion_message() {
    echo ""
    echo "=================================================="
    echo "         CLEANUP COMPLETED"
    echo "=================================================="
    echo ""
    log_success "Matomo AWS infrastructure has been removed"
    echo ""
    echo "📋 What was cleaned up:"
    echo "   ✅ All AWS resources (EC2, RDS, VPC, etc.)"
    echo "   ✅ SSH keys and secrets"
    echo "   ✅ Local temporary files"
    echo ""
    echo "💰 AWS charges for these resources have stopped"
    echo ""
    echo "🔄 To redeploy: ./scripts/deploy.sh"
    echo ""
}

# Handle cleanup errors
handle_cleanup_errors() {
    echo ""
    log_error "Cleanup encountered errors"
    echo ""
    echo "🔧 Manual cleanup may be required:"
    echo "   1. Check AWS CloudFormation Console for stuck stacks"
    echo "   2. Check EC2 Console for running instances"
    echo "   3. Check RDS Console for databases"
    echo "   4. Check VPC Console for VPCs and NAT Gateways"
    echo "   5. Check Secrets Manager for unused secrets"
    echo ""
    echo "💡 Common issues:"
    echo "   - RDS instances may take time to delete"
    echo "   - Security groups may have dependencies"
    echo "   - NAT Gateways may need manual deletion"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "🧹 Matomo AWS Server Cleanup"
    echo "============================="
    echo ""
    
    check_prerequisites
    get_project_config
    show_deletion_plan
    confirm_deletion
    
    log_info "Starting cleanup process..."
    
    if destroy_stacks; then
        cleanup_local_files
        if verify_cleanup; then
            show_completion_message
        else
            handle_cleanup_errors
            exit 1
        fi
    else
        handle_cleanup_errors
        exit 1
    fi
    
    log_success "Cleanup process completed!"
}

# Run main function
main "$@"