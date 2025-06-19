#!/bin/bash

# Matomo AWS Server Installation Validation Script
# Validates that Matomo web interface is accessible and properly configured

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

# Configuration
TIMEOUT=10
MAX_RETRIES=3
WAIT_MODE=false
WAIT_TIMEOUT=900  # 15 minutes default
RETRY_INTERVAL=30  # 30 seconds between retries

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

# Check if required tools are available
check_dependencies() {
    local missing_tools=()
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Dependencies check passed"
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
    
    log_success "Project configuration loaded: $PROJECT_NAME"
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

# Get Matomo server details
get_server_details() {
    local compute_stack="${PROJECT_NAME}-compute"
    
    # Check if compute stack exists
    if ! aws cloudformation describe-stacks --stack-name "$compute_stack" &> /dev/null; then
        log_error "Compute stack not found. Has the deployment completed?"
        exit 1
    fi
    
    INSTANCE_ID=$(get_stack_output "$compute_stack" "InstanceId")
    PUBLIC_IP=$(get_stack_output "$compute_stack" "PublicIp")
    MATOMO_URL=$(get_stack_output "$compute_stack" "MatomoUrl")
    SSH_KEY_PARAM=$(get_stack_output "$compute_stack" "SshKeyParameterName")
    
    if [ "$INSTANCE_ID" = "N/A" ] || [ "$PUBLIC_IP" = "N/A" ]; then
        log_error "Could not retrieve server details from CloudFormation stack"
        exit 1
    fi
    
    log_success "Server details retrieved: $PUBLIC_IP ($INSTANCE_ID)"
}

# Test HTTP connectivity
test_http_connectivity() {
    log_info "Testing HTTP connectivity to $MATOMO_URL..."
    
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT "$MATOMO_URL" > /dev/null 2>&1; then
            log_success "HTTP connectivity successful"
            return 0
        else
            ((retry_count++))
            if [ $retry_count -lt $MAX_RETRIES ]; then
                log_info "Retry $retry_count/$MAX_RETRIES in 5 seconds..."
                sleep 5
            fi
        fi
    done
    
    log_error "HTTP connectivity failed after $MAX_RETRIES attempts"
    return 1
}

# Check if Matomo is responding and determine its state
validate_matomo_response() {
    log_info "Checking Matomo web interface state..."
    
    local response=$(curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT "$MATOMO_URL" 2>/dev/null || echo "")
    
    if [[ "$response" == *"Matomo"* ]] || [[ "$response" == *"matomo"* ]]; then
        # Check what type of Matomo page we're seeing
        if [[ "$response" == *"Installation"* ]] || [[ "$response" == *"installation"* ]] || [[ "$response" == *"setup"* ]] || [[ "$response" == *"Setup"* ]]; then
            log_success "Matomo setup wizard is active and ready for configuration"
            log_info "Next step: Complete the web-based setup at $MATOMO_URL"
            return 0
        elif [[ "$response" == *"login"* ]] || [[ "$response" == *"Login"* ]] || [[ "$response" == *"dashboard"* ]] || [[ "$response" == *"Dashboard"* ]]; then
            log_success "Matomo is fully configured and operational"
            log_info "Matomo dashboard/login interface is accessible"
            return 0
        else
            # Generic Matomo response - try to determine state
            log_success "Matomo web interface is responding"
            log_info "Matomo state: Accessible but specific state unclear"
            return 0
        fi
    elif [[ "$response" == *"Apache"* ]] || [[ "$response" == *"nginx"* ]]; then
        log_warning "Web server is responding but Matomo is not accessible"
        log_info "This may indicate Matomo installation is incomplete"
        return 1
    elif [ -n "$response" ]; then
        log_warning "Server is responding but content doesn't appear to be Matomo"
        return 1
    else
        log_error "No response from Matomo web interface"
        return 1
    fi
}

# Check HTTP status codes
check_http_status() {
    log_info "Checking HTTP status codes..."
    
    local status_code=$(curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT -o /dev/null -w "%{http_code}" "$MATOMO_URL" 2>/dev/null || echo "000")
    
    case $status_code in
        200)
            log_success "HTTP status: 200 OK"
            ;;
        301|302|303|307|308)
            log_success "HTTP status: $status_code (redirect - normal for Matomo setup)"
            ;;
        403)
            log_warning "HTTP status: 403 Forbidden - check file permissions"
            ;;
        404)
            log_error "HTTP status: 404 Not Found - Matomo may not be installed"
            ;;
        500|502|503|504)
            log_error "HTTP status: $status_code - server error"
            ;;
        000)
            log_error "HTTP status: Connection failed"
            ;;
        *)
            log_warning "HTTP status: $status_code (unexpected)"
            ;;
    esac
}

# Check SSL/HTTPS if configured
check_ssl_configuration() {
    log_info "Checking SSL/HTTPS configuration..."
    
    local https_url="https://$PUBLIC_IP"
    local ssl_status=$(curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT -k -o /dev/null -w "%{http_code}" "$https_url" 2>/dev/null || echo "000")
    
    if [ "$ssl_status" = "200" ] || [ "$ssl_status" = "301" ] || [ "$ssl_status" = "302" ]; then
        log_success "HTTPS is configured and responding"
        
        # Check if HTTPS redirect is working
        local redirect_location=$(curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT -I "$MATOMO_URL" | grep -i "location:" | head -1)
        if [[ "$redirect_location" == *"https://"* ]]; then
            log_success "HTTP to HTTPS redirect is configured"
        else
            log_warning "HTTP to HTTPS redirect may not be configured"
        fi
    else
        log_info "HTTPS not configured (status: $ssl_status) - using HTTP only"
    fi
}

# Wait for Matomo installation to complete
wait_for_matomo_installation() {
    if [ "$WAIT_MODE" != true ]; then
        return 0
    fi
    
    log_info "Wait mode enabled - monitoring installation progress..."
    log_info "Timeout: ${WAIT_TIMEOUT}s, Check interval: ${RETRY_INTERVAL}s"
    
    local start_time=$(date +%s)
    local attempt=1
    local max_attempts=$((WAIT_TIMEOUT / RETRY_INTERVAL))
    
    echo ""
    echo -e "${CYAN}⏳ Waiting for Matomo Installation${NC}"
    echo "=================================="
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $WAIT_TIMEOUT ]; then
            log_error "Installation timeout reached (${WAIT_TIMEOUT}s) - giving up"
            return 1
        fi
        
        log_info "Attempt $attempt/$max_attempts (${elapsed}s elapsed)..."
        
        # Test HTTP connectivity first
        if curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT "$MATOMO_URL" > /dev/null 2>&1; then
            # Test Matomo response
            local response=$(curl -s --connect-timeout $TIMEOUT --max-time $TIMEOUT "$MATOMO_URL" 2>/dev/null || echo "")
            
            if [[ "$response" == *"Matomo"* ]] || [[ "$response" == *"matomo"* ]]; then
                log_success "Matomo is now accessible and ready!"
                log_info "Matomo has been successfully deployed and is responding"
                return 0
            else
                log_info "Server responding but Matomo not ready yet, waiting ${RETRY_INTERVAL}s..."
            fi
        else
            log_info "Server not responding yet, waiting ${RETRY_INTERVAL}s..."
        fi
        
        # Check installation logs for progress/errors
        check_installation_progress
        
        sleep $RETRY_INTERVAL
        ((attempt++))
    done
}

# Check installation progress via logs
check_installation_progress() {
    if [ "$SSH_KEY_PARAM" = "N/A" ]; then
        return 0
    fi
    
    # Quick check of installation status without logging
    local temp_key_file="/tmp/matomo-progress-key.pem"
    if aws ssm get-parameter --name "$SSH_KEY_PARAM" --with-decryption --query 'Parameter.Value' --output text > "$temp_key_file" 2>/dev/null; then
        chmod 400 "$temp_key_file"
        
        # Check for completion markers
        local install_complete=$(ssh -i "$temp_key_file" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "ec2-user@$PUBLIC_IP" \
            "grep -i 'installation.*complete\|matomo.*ready\|setup.*finished' /var/log/matomo-install.log 2>/dev/null | tail -1" 2>/dev/null || echo "")
        
        if [ -n "$install_complete" ]; then
            log_info "Progress: $install_complete"
        fi
        
        # Check for recent errors
        local recent_errors=$(ssh -i "$temp_key_file" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "ec2-user@$PUBLIC_IP" \
            "tail -10 /var/log/matomo-install.log 2>/dev/null | grep -i 'error\|fail' | tail -1" 2>/dev/null || echo "")
        
        if [ -n "$recent_errors" ]; then
            log_warning "Recent log entry: $recent_errors"
        fi
        
        rm -f "$temp_key_file"
    fi
}

# Check for common Matomo files and directories
validate_matomo_structure() {
    log_info "Validating Matomo file structure via HTTP..."
    
    local base_url="$MATOMO_URL"
    local matomo_files=(
        "/index.php"
        "/matomo.php"
        "/piwik.php"
        "/js/piwik.min.js"
        "/piwik.js"
    )
    
    local found_files=0
    for file in "${matomo_files[@]}"; do
        local status=$(curl -s --connect-timeout 5 --max-time 5 -o /dev/null -w "%{http_code}" "${base_url}${file}" 2>/dev/null || echo "000")
        if [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
            ((found_files++))
        fi
    done
    
    if [ $found_files -ge 2 ]; then
        log_success "Matomo core files are accessible ($found_files/${#matomo_files[@]} files found)"
    elif [ $found_files -eq 1 ]; then
        log_warning "Some Matomo files found but installation may be incomplete"
    else
        log_error "No Matomo core files found - installation may have failed"
    fi
}

# Check server logs via SSH (if possible)
check_installation_logs() {
    log_info "Attempting to check installation logs..."
    
    if [ "$SSH_KEY_PARAM" = "N/A" ]; then
        log_warning "SSH key parameter not available - cannot check installation logs"
        return 0
    fi
    
    # Try to get SSH key
    local temp_key_file="/tmp/matomo-validation-key.pem"
    if aws ssm get-parameter --name "$SSH_KEY_PARAM" --with-decryption --query 'Parameter.Value' --output text > "$temp_key_file" 2>/dev/null; then
        chmod 400 "$temp_key_file"
        
        # Check if installation log exists
        if ssh -i "$temp_key_file" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "ec2-user@$PUBLIC_IP" "test -f /var/log/matomo-install.log" 2>/dev/null; then
            log_success "Installation log found on server"
            
            # Check for successful installation markers
            local install_status=$(ssh -i "$temp_key_file" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "ec2-user@$PUBLIC_IP" "tail -20 /var/log/matomo-install.log | grep -i 'success\|complete\|done'" 2>/dev/null || echo "")
            
            if [ -n "$install_status" ]; then
                log_success "Installation appears to have completed successfully"
            else
                local error_status=$(ssh -i "$temp_key_file" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "ec2-user@$PUBLIC_IP" "tail -20 /var/log/matomo-install.log | grep -i 'error\|fail'" 2>/dev/null || echo "")
                if [ -n "$error_status" ]; then
                    log_warning "Installation log contains errors - check server logs"
                else
                    log_warning "Installation status unclear from logs"
                fi
            fi
        else
            log_warning "Installation log not found - installation may still be in progress"
        fi
        
        # Check if installation status file exists
        if ssh -i "$temp_key_file" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "ec2-user@$PUBLIC_IP" "test -f /var/www/html/INSTALLATION_STATUS" 2>/dev/null; then
            local status_content=$(ssh -i "$temp_key_file" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "ec2-user@$PUBLIC_IP" "cat /var/www/html/INSTALLATION_STATUS" 2>/dev/null || echo "")
            if [ -n "$status_content" ]; then
                log_success "Installation status: $status_content"
            fi
        fi
        
        # Clean up temp key file
        rm -f "$temp_key_file"
    else
        log_warning "Could not retrieve SSH key - unable to check installation logs"
    fi
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --wait)
                WAIT_MODE=true
                shift
                ;;
            --timeout)
                WAIT_TIMEOUT="$2"
                shift 2
                ;;
            --interval)
                RETRY_INTERVAL="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Validates Matomo installation and web interface accessibility"
    echo ""
    echo "Options:"
    echo "  --wait              Enable wait mode - retry until installation completes"
    echo "  --timeout SECONDS   Wait timeout in seconds (default: 900 = 15 minutes)"
    echo "  --interval SECONDS  Retry interval in seconds (default: 30)"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run validation once"
    echo "  $0 --wait            # Wait for installation to complete (15 min timeout)"
    echo "  $0 --wait --timeout 1800  # Wait with 30 minute timeout"
}

# Main validation function
run_validation() {
    echo ""
    echo "=================================================="
    echo "      MATOMO INSTALLATION VALIDATION"
    echo "=================================================="
    echo ""
    
    check_dependencies
    get_project_config
    get_server_details
    
    # If wait mode is enabled, wait for installation first
    if [ "$WAIT_MODE" = true ]; then
        wait_for_matomo_installation
        local wait_result=$?
        
        if [ $wait_result -ne 0 ]; then
            echo ""
            echo "=================================================="
            echo "              VALIDATION SUMMARY"
            echo "=================================================="
            echo -e "❌ ${RED}Installation timeout or failure${NC}"
            echo ""
            echo "The installation did not complete within the specified timeout."
            echo "You can try running the validation again or check the server manually."
            exit 1
        fi
        
        # Reset counters after wait mode
        PASSED=0
        FAILED=0
        WARNINGS=0
    fi
    
    echo ""
    echo -e "${CYAN}🌐 Testing Network Connectivity${NC}"
    echo "==============================="
    test_http_connectivity
    
    echo ""
    echo -e "${CYAN}🔍 Determining Matomo State${NC}"
    echo "=========================="
    check_http_status
    validate_matomo_response
    local matomo_state=$?
    
    # Based on the state, decide whether to continue with additional checks
    if [ $matomo_state -eq 0 ]; then
        echo ""
        echo -e "${CYAN}✅ Additional Information${NC}"
        echo "========================"
        
        echo ""
        echo -e "${CYAN}🔒 SSL Configuration${NC}"
        echo "===================="
        check_ssl_configuration
        
        echo ""
        echo -e "${CYAN}📁 Matomo Structure${NC}"
        echo "==================="
        validate_matomo_structure
    else
        echo ""
        log_info "Skipping additional checks due to Matomo accessibility issues"
    fi
    
    echo ""
    echo "=================================================="
    echo "              VALIDATION SUMMARY"
    echo "=================================================="
    echo -e "✅ ${GREEN}Passed:${NC} $PASSED"
    echo -e "⚠️  ${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "❌ ${RED}Failed:${NC} $FAILED"
    echo ""
    
    echo -e "${CYAN}🔗 Quick Access${NC}"
    echo "==============="
    echo "Matomo URL: $MATOMO_URL"
    echo "Server IP:  $PUBLIC_IP"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        if [ $WARNINGS -eq 0 ]; then
            echo -e "${GREEN}🎉 Matomo installation validation passed!${NC}"
            echo "Your Matomo instance is ready to use at: $MATOMO_URL"
            exit 0
        else
            echo -e "${YELLOW}✅ Matomo is accessible with $WARNINGS warnings${NC}"
            echo "Your Matomo instance is available at: $MATOMO_URL"
            echo "Consider reviewing the warnings above for optimal configuration."
            exit 0
        fi
    else
        echo -e "${RED}❌ Matomo installation validation failed with $FAILED errors${NC}"
        echo ""
        echo "Troubleshooting suggestions:"
        echo "- Wait a few more minutes for installation to complete"
        echo "- Check server logs: ssh -i matomo-key.pem ec2-user@$PUBLIC_IP 'sudo tail -f /var/log/matomo-install.log'"
        echo "- Verify security group allows HTTP traffic on port 80"
        echo "- Check EC2 instance status in AWS console"
        exit 1
    fi
}

# Parse arguments and run main function
parse_arguments "$@"
run_validation