#!/bin/bash

# Matomo Database Password Retrieval Script
# This script retrieves the database credentials from AWS Secrets Manager

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

# Check if stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" &> /dev/null
}

# Get database credentials
get_database_credentials() {
    local database_stack="${PROJECT_NAME}-database"
    
    # Check if database is enabled
    if [ "$ENABLE_DATABASE" != "true" ] && [ "$ENABLE_DATABASE" != "True" ]; then
        log_error "Database is not enabled in the configuration (enableDatabase: false)"
        echo "To enable database, set 'enableDatabase' to true in cdk.json and redeploy."
        exit 1
    fi
    
    # Check if database stack exists
    if ! stack_exists "$database_stack"; then
        log_error "Database stack '$database_stack' not found."
        echo "Make sure the database stack has been deployed successfully."
        exit 1
    fi
    
    log_info "Retrieving database credentials from AWS Secrets Manager..."
    
    # Get the secret ARN from CloudFormation output
    local secret_arn=$(aws cloudformation describe-stacks \
        --stack-name "$database_stack" \
        --query "Stacks[0].Outputs[?OutputKey=='DatabaseSecretArn'].OutputValue" \
        --output text 2>/dev/null)
    
    if [ -z "$secret_arn" ] || [ "$secret_arn" = "None" ]; then
        log_error "Could not find database secret ARN in stack outputs"
        exit 1
    fi
    
    log_info "Secret ARN: $secret_arn"
    
    # Retrieve the secret value
    local secret_json=$(aws secretsmanager get-secret-value \
        --secret-id "$secret_arn" \
        --query 'SecretString' \
        --output text 2>/dev/null)
    
    if [ -z "$secret_json" ]; then
        log_error "Could not retrieve secret from Secrets Manager"
        exit 1
    fi
    
    # Use python if available (from venv), otherwise python3
    local python_cmd="python3"
    if command -v python &> /dev/null; then
        python_cmd="python"
    fi
    
    # Parse and display credentials
    local username=$(echo "$secret_json" | $python_cmd -c "import sys, json; print(json.load(sys.stdin)['username'])" 2>/dev/null)
    local password=$(echo "$secret_json" | $python_cmd -c "import sys, json; print(json.load(sys.stdin)['password'])" 2>/dev/null)
    
    if [ -z "$username" ] || [ -z "$password" ]; then
        log_error "Could not parse credentials from secret"
        exit 1
    fi
    
    echo ""
    echo "=================================================="
    echo "         DATABASE CREDENTIALS"
    echo "=================================================="
    echo ""
    echo "Username: $username"
    echo "Password: $password"
    echo ""
    echo "Secret ARN: $secret_arn"
    echo ""
    
    # Get additional database info
    local db_endpoint=$(aws cloudformation describe-stacks \
        --stack-name "$database_stack" \
        --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" \
        --output text 2>/dev/null)
    
    local db_port=$(aws cloudformation describe-stacks \
        --stack-name "$database_stack" \
        --query "Stacks[0].Outputs[?OutputKey=='DatabasePort'].OutputValue" \
        --output text 2>/dev/null)
    
    local db_name=$(aws cloudformation describe-stacks \
        --stack-name "$database_stack" \
        --query "Stacks[0].Outputs[?OutputKey=='DatabaseName'].OutputValue" \
        --output text 2>/dev/null)
    
    if [ "$db_endpoint" != "None" ]; then
        echo "Database Endpoint: $db_endpoint"
    fi
    if [ "$db_port" != "None" ]; then
        echo "Database Port: $db_port"
    fi
    if [ "$db_name" != "None" ]; then
        echo "Database Name: $db_name"
    fi
    echo ""
    
    log_success "Database credentials retrieved successfully!"
}

# Main execution
main() {
    echo ""
    echo "🔐 Matomo Database Password Retrieval"
    echo "====================================="
    echo ""
    
    check_aws_cli
    get_project_config
    get_database_credentials
}

# Run main function
main "$@"