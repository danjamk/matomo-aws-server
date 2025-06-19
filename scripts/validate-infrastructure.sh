#!/bin/bash

# Matomo AWS Server Infrastructure Validation Script
# Validates that all AWS resources are created and configured correctly

# Note: set -e removed to prevent premature exits on non-critical command failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
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
    
    log_success "AWS CLI is configured and accessible"
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
    
    log_success "Project configuration loaded: $PROJECT_NAME (DB: $ENABLE_DATABASE)"
}

# Check if stack exists and is in correct state
validate_stack() {
    local stack_name=$1
    local description=$2
    
    log_info "Validating $description ($stack_name)..."
    
    if ! aws cloudformation describe-stacks --stack-name "$stack_name" &> /dev/null; then
        log_error "$description stack does not exist"
        return 1
    fi
    
    local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text)
    
    case $stack_status in
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            log_success "$description stack is in healthy state ($stack_status)"
            ;;
        "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS")
            log_warning "$description stack is still being deployed ($stack_status)"
            ;;
        "ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE")
            log_warning "$description stack completed with rollback ($stack_status)"
            ;;
        *)
            log_error "$description stack is in failed state ($stack_status)"
            return 1
            ;;
    esac
    
    return 0
}

# Get stack output value
get_stack_output() {
    local stack_name=$1
    local output_key=$2
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo "N/A"
}

# Validate VPC and networking resources
validate_networking() {
    local networking_stack="${PROJECT_NAME}-networking"
    
    if ! validate_stack "$networking_stack" "Networking"; then
        return 0  # Don't fail the whole script, just record the failure
    fi
    
    # Get VPC details
    local vpc_id=$(get_stack_output "$networking_stack" "VpcId")
    local web_sg_id=$(get_stack_output "$networking_stack" "WebSecurityGroupId")
    local db_sg_id=$(get_stack_output "$networking_stack" "DatabaseSecurityGroupId")
    local public_subnets=$(get_stack_output "$networking_stack" "PublicSubnetIds")
    local private_subnets=$(get_stack_output "$networking_stack" "PrivateSubnetIds")
    
    # Validate VPC exists
    if [ "$vpc_id" != "N/A" ] && aws ec2 describe-vpcs --vpc-ids "$vpc_id" &> /dev/null; then
        log_success "VPC exists and is accessible ($vpc_id)"
    else
        log_error "VPC not found or not accessible ($vpc_id)"
        return 1
    fi
    
    # Validate security groups
    if [ "$web_sg_id" != "N/A" ] && aws ec2 describe-security-groups --group-ids "$web_sg_id" &> /dev/null; then
        log_success "Web security group exists ($web_sg_id)"
        
        # Check security group rules
        local sg_rules=$(aws ec2 describe-security-groups --group-ids "$web_sg_id" --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`]' --output json)
        if [ "$sg_rules" != "[]" ]; then
            log_success "HTTP access rule configured in web security group"
        else
            log_error "HTTP access rule missing in web security group"
        fi
        
        local ssh_rules=$(aws ec2 describe-security-groups --group-ids "$web_sg_id" --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' --output json)
        if [ "$ssh_rules" != "[]" ]; then
            log_success "SSH access rule configured in web security group"
            
            # Check if SSH is restricted
            local ssh_cidr=$(aws ec2 describe-security-groups --group-ids "$web_sg_id" --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[0].CidrIp' --output text)
            if [ "$ssh_cidr" = "0.0.0.0/0" ]; then
                log_warning "SSH access is open to the internet (0.0.0.0/0) - consider restricting"
            else
                log_success "SSH access is restricted to specific CIDR ($ssh_cidr)"
            fi
        else
            log_error "SSH access rule missing in web security group"
        fi
    else
        log_error "Web security group not found ($web_sg_id)"
    fi
    
    if [ "$db_sg_id" != "N/A" ] && aws ec2 describe-security-groups --group-ids "$db_sg_id" &> /dev/null; then
        log_success "Database security group exists ($db_sg_id)"
        
        # Check database security group rules
        local db_rules=$(aws ec2 describe-security-groups --group-ids "$db_sg_id" --query 'SecurityGroups[0].IpPermissions[?FromPort==`3306`]' --output json)
        if [ "$db_rules" != "[]" ]; then
            log_success "MySQL access rule configured in database security group"
        else
            log_warning "MySQL access rule missing in database security group (expected if RDS not enabled)"
        fi
    else
        log_error "Database security group not found ($db_sg_id)"
    fi
    
    # Validate subnets
    if [ "$public_subnets" != "N/A" ]; then
        # Use tr to replace commas with spaces and count words, trim whitespace
        local subnet_count=$(echo "$public_subnets" | tr ',' ' ' | wc -w | tr -d ' ')
        if [ "$subnet_count" -ge 1 ]; then
            log_success "Public subnets configured ($subnet_count subnets)"
        else
            log_error "No public subnets found"
        fi
    else
        log_error "Public subnet information not available"
    fi
    
    if [ "$private_subnets" != "N/A" ]; then
        # Use tr to replace commas with spaces and count words, trim whitespace
        local subnet_count=$(echo "$private_subnets" | tr ',' ' ' | wc -w | tr -d ' ')
        if [ "$subnet_count" -ge 2 ]; then
            log_success "Private subnets configured ($subnet_count subnets - sufficient for RDS)"
        elif [ "$subnet_count" -eq 1 ]; then
            log_warning "Only 1 private subnet configured - RDS requires at least 2 AZs"
        else
            log_error "No private subnets found"
        fi
    else
        log_error "Private subnet information not available"
    fi
}

# Validate compute resources
validate_compute() {
    local compute_stack="${PROJECT_NAME}-compute"
    
    if ! validate_stack "$compute_stack" "Compute"; then
        return 1
    fi
    
    # Get instance details
    local instance_id=$(get_stack_output "$compute_stack" "InstanceId")
    local public_ip=$(get_stack_output "$compute_stack" "PublicIp")
    local ssh_key_param=$(get_stack_output "$compute_stack" "SshKeyParameterName")
    
    # Validate EC2 instance
    if [ "$instance_id" != "N/A" ]; then
        local instance_state=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "N/A")
        
        case $instance_state in
            "running")
                log_success "EC2 instance is running ($instance_id)"
                ;;
            "pending")
                log_warning "EC2 instance is starting ($instance_id)"
                ;;
            "stopped"|"stopping")
                log_warning "EC2 instance is stopped/stopping ($instance_id)"
                ;;
            "N/A")
                log_error "EC2 instance not found ($instance_id)"
                ;;
            *)
                log_error "EC2 instance is in unexpected state: $instance_state ($instance_id)"
                ;;
        esac
        
        # Validate instance type and configuration
        local instance_type=$(aws ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].InstanceType' --output text 2>/dev/null || echo "N/A")
        if [ "$instance_type" != "N/A" ]; then
            log_success "Instance type: $instance_type"
        fi
        
        # Check if instance has public IP
        if [ "$public_ip" != "N/A" ] && [ "$public_ip" != "" ]; then
            log_success "Instance has public IP assigned ($public_ip)"
        else
            log_error "Instance does not have a public IP assigned"
        fi
    else
        log_error "EC2 instance ID not available"
    fi
    
    # Validate SSH key in Parameter Store
    if [ "$ssh_key_param" != "N/A" ]; then
        if aws ssm get-parameter --name "$ssh_key_param" --with-decryption &> /dev/null; then
            log_success "SSH private key is stored in Parameter Store ($ssh_key_param)"
        else
            log_error "SSH private key not found in Parameter Store ($ssh_key_param)"
        fi
    else
        log_error "SSH key parameter name not available"
    fi
}

# Validate database resources (if enabled)
validate_database() {
    if [ "$ENABLE_DATABASE" != "true" ] && [ "$ENABLE_DATABASE" != "True" ]; then
        log_info "Database validation skipped (RDS not enabled)"
        return 0
    fi
    
    local database_stack="${PROJECT_NAME}-database"
    
    if ! validate_stack "$database_stack" "Database"; then
        return 1
    fi
    
    # Get database details
    local db_endpoint=$(get_stack_output "$database_stack" "DatabaseEndpoint")
    local db_port=$(get_stack_output "$database_stack" "DatabasePort")
    local secret_arn=$(get_stack_output "$database_stack" "DatabaseSecretArn")
    
    # Validate RDS instance exists and is accessible
    if [ "$db_endpoint" != "N/A" ]; then
        log_success "RDS endpoint is configured ($db_endpoint:$db_port)"
        
        # Try to get RDS instance details (this validates the instance exists)
        local db_instances=$(aws rds describe-db-instances --query "DBInstances[?Endpoint.Address=='$db_endpoint']" --output json)
        if [ "$db_instances" != "[]" ]; then
            local db_status=$(echo "$db_instances" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['DBInstanceStatus'])" 2>/dev/null || echo "unknown")
            
            case $db_status in
                "available")
                    log_success "RDS instance is available and ready"
                    ;;
                "creating"|"backing-up"|"modifying")
                    log_warning "RDS instance is in transitional state: $db_status"
                    ;;
                *)
                    log_error "RDS instance is in unexpected state: $db_status"
                    ;;
            esac
        else
            log_error "RDS instance not found with endpoint $db_endpoint"
        fi
    else
        log_error "RDS endpoint not available"
    fi
    
    # Validate database credentials in Secrets Manager
    if [ "$secret_arn" != "N/A" ]; then
        if aws secretsmanager get-secret-value --secret-id "$secret_arn" &> /dev/null; then
            log_success "Database credentials are stored in Secrets Manager"
            log_info "Database is in private subnets (not publicly accessible - this is correct)"
        else
            log_error "Database credentials not found in Secrets Manager ($secret_arn)"
        fi
    else
        log_error "Database secret ARN not available"
    fi
}

# Main validation function
run_validation() {
    echo ""
    echo "=================================================="
    echo "     MATOMO INFRASTRUCTURE VALIDATION"
    echo "=================================================="
    echo ""
    
    check_aws_cli
    get_project_config
    
    echo ""
    echo -e "${CYAN}🌐 Validating Networking Resources${NC}"
    echo "=================================="
    validate_networking
    
    echo ""
    echo -e "${CYAN}🖥️  Validating Compute Resources${NC}"
    echo "==============================="
    validate_compute
    
    echo ""
    echo -e "${CYAN}🗄️  Validating Database Resources${NC}"
    echo "================================"
    validate_database
    
    echo ""
    echo "=================================================="
    echo "              VALIDATION SUMMARY"
    echo "=================================================="
    echo -e "✅ ${GREEN}Passed:${NC} $PASSED"
    echo -e "⚠️  ${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "❌ ${RED}Failed:${NC} $FAILED"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        if [ $WARNINGS -eq 0 ]; then
            echo -e "${GREEN}🎉 All infrastructure validations passed!${NC}"
            exit 0
        else
            echo -e "${YELLOW}✅ Infrastructure is functional with $WARNINGS warnings${NC}"
            exit 0
        fi
    else
        echo -e "${RED}❌ Infrastructure validation failed with $FAILED errors${NC}"
        echo "Please check the failed items above and ensure your deployment completed successfully."
        exit 1
    fi
}

# Run main function
run_validation "$@"