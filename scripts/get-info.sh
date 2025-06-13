#!/bin/bash

# Matomo AWS Server Information Retrieval Script
# This script retrieves and displays all connection details for your Matomo deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Check if AWS CLI is available
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
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

# Get stack outputs
get_stack_outputs() {
    local stack_name=$1
    local output_key=$2
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo "N/A"
}

# Check if stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" &> /dev/null
}

# Get SSH key from Parameter Store
get_ssh_key() {
    local key_param_name=$1
    if [ "$key_param_name" != "N/A" ]; then
        log_info "Retrieving SSH private key..."
        aws ssm get-parameter \
            --name "$key_param_name" \
            --with-decryption \
            --query 'Parameter.Value' \
            --output text > matomo-key.pem 2>/dev/null
        
        if [ $? -eq 0 ]; then
            chmod 400 matomo-key.pem
            log_success "SSH key saved to: matomo-key.pem"
            return 0
        else
            log_warning "Could not retrieve SSH key from Parameter Store"
            return 1
        fi
    fi
    return 1
}

# Get database credentials
get_database_credentials() {
    local secret_arn=$1
    if [ "$secret_arn" != "N/A" ]; then
        log_info "Database credentials are stored in AWS Secrets Manager"
        echo "Secret ARN: $secret_arn"
        
        # Try to retrieve and display username (password is sensitive)
        # Use python if available (from venv), otherwise python3
        local python_cmd="python3"
        if command -v python &> /dev/null; then
            python_cmd="python"
        fi
        
        local username=$(aws secretsmanager get-secret-value \
            --secret-id "$secret_arn" \
            --query 'SecretString' \
            --output text 2>/dev/null | \
            $python_cmd -c "import sys, json; print(json.load(sys.stdin)['username'])" 2>/dev/null || echo "N/A")
        
        if [ "$username" != "N/A" ]; then
            echo "Database Username: $username"
            echo "Database Password: <stored in secrets manager>"
        fi
    fi
}

# Check deployment status
check_deployment_status() {
    local public_ip=$1
    if [ "$public_ip" != "N/A" ]; then
        log_info "Checking Matomo installation status..."
        
        # Try to reach the server
        if curl -s --connect-timeout 5 "http://$public_ip" > /dev/null 2>&1; then
            log_success "Matomo server is responding"
        else
            log_warning "Matomo server is not responding yet (may still be installing)"
        fi
        
        # Check if installation status file exists via SSH
        echo "To check installation progress, SSH into the server and run:"
        echo "  cat /var/log/matomo-install.log"
        echo "  cat /var/www/html/INSTALLATION_STATUS"
    fi
}

# Main function to display all information
display_deployment_info() {
    echo ""
    echo "=================================================="
    echo "         MATOMO DEPLOYMENT INFORMATION"
    echo "=================================================="
    echo ""
    
    local networking_stack="${PROJECT_NAME}-networking"
    local database_stack="${PROJECT_NAME}-database"
    local compute_stack="${PROJECT_NAME}-compute"
    
    # Check if stacks exist
    if ! stack_exists "$networking_stack"; then
        log_error "Networking stack not found. Has the deployment completed?"
        exit 1
    fi
    
    if ! stack_exists "$compute_stack"; then
        log_error "Compute stack not found. Has the deployment completed?"
        exit 1
    fi
    
    # Get networking information
    echo -e "${CYAN}🌐 NETWORKING${NC}"
    echo "=============="
    local vpc_id=$(get_stack_outputs "$networking_stack" "VpcId")
    local web_sg_id=$(get_stack_outputs "$networking_stack" "WebSecurityGroupId")
    local db_sg_id=$(get_stack_outputs "$networking_stack" "DatabaseSecurityGroupId")
    
    echo "VPC ID: $vpc_id"
    echo "Web Security Group: $web_sg_id"
    echo "Database Security Group: $db_sg_id"
    echo ""
    
    # Get compute information
    echo -e "${CYAN}🖥️  COMPUTE${NC}"
    echo "============"
    local instance_id=$(get_stack_outputs "$compute_stack" "InstanceId")
    local public_ip=$(get_stack_outputs "$compute_stack" "PublicIp")
    local public_dns=$(get_stack_outputs "$compute_stack" "PublicDns")
    local matomo_url=$(get_stack_outputs "$compute_stack" "MatomoUrl")
    local ssh_key_param=$(get_stack_outputs "$compute_stack" "SshKeyParameterName")
    
    echo "Instance ID: $instance_id"
    echo "Public IP: $public_ip"
    echo "Public DNS: $public_dns"
    echo "Matomo URL: $matomo_url"
    echo ""
    
    # Get database information if enabled
    if [ "$ENABLE_DATABASE" = "true" ] || [ "$ENABLE_DATABASE" = "True" ]; then
        if stack_exists "$database_stack"; then
            echo -e "${CYAN}🗄️  DATABASE${NC}"
            echo "============="
            local db_endpoint=$(get_stack_outputs "$database_stack" "DatabaseEndpoint")
            local db_port=$(get_stack_outputs "$database_stack" "DatabasePort")
            local db_name=$(get_stack_outputs "$database_stack" "DatabaseName")
            local secret_arn=$(get_stack_outputs "$database_stack" "DatabaseSecretArn")
            
            echo "RDS Endpoint: $db_endpoint"
            echo "Port: $db_port"
            echo "Database Name: $db_name"
            echo ""
            get_database_credentials "$secret_arn"
        else
            log_warning "Database stack not found (may not be deployed yet)"
        fi
    else
        echo -e "${CYAN}🗄️  DATABASE${NC}"
        echo "============="
        echo "Database: RDS MySQL deployment not enabled"
    fi
    echo ""
    
    # SSH Access
    echo -e "${CYAN}🔐 SSH ACCESS${NC}"
    echo "=============="
    if get_ssh_key "$ssh_key_param"; then
        echo "SSH Command: ssh -i matomo-key.pem ec2-user@$public_ip"
    else
        echo "Manual SSH key retrieval:"
        echo "aws ssm get-parameter --name '$ssh_key_param' --with-decryption --query 'Parameter.Value' --output text > matomo-key.pem"
        echo "chmod 400 matomo-key.pem"
        echo "ssh -i matomo-key.pem ec2-user@$public_ip"
    fi
    echo ""
    
    # Quick actions
    echo -e "${CYAN}⚡ QUICK ACTIONS${NC}"
    echo "================"
    echo "Open Matomo:     open $matomo_url"
    echo "SSH to server:   ssh -i matomo-key.pem ec2-user@$public_ip"
    echo "View logs:       ssh -i matomo-key.pem ec2-user@$public_ip 'sudo tail -f /var/log/matomo-install.log'"
    echo "Cleanup:         ./scripts/cleanup.sh"
    echo ""
    
    # Check status
    check_deployment_status "$public_ip"
}

# Main execution
main() {
    log_info "Retrieving Matomo deployment information..."
    
    check_aws_cli
    get_project_config
    display_deployment_info
    
    log_success "Information retrieval completed!"
}

# Run main function
main "$@"