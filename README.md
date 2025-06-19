# Matomo AWS Server
Deploy Matomo web analytics on AWS EC2 with CDK - cost-optimized and production-ready.

This CDK project provides infrastructure-as-code deployment for a self-hosted Matomo analytics server on AWS. 
By deploying your own Matomo instance, you gain full data ownership, eliminate sampling limitations, and consolidate 
multiple marketing tools (heatmaps, A/B testing, attribution) into a single platform. This approach is particularly 
valuable for Shopify stores requiring custom analytics, first-party data control, and the ability to join visitor 
data with customer databases for advanced attribution modeling. The deployment includes EC2 instance provisioning, 
RDS MySQL setup, and basic security configurations to get you up and running quickly.

The following article talks a bit more about the motivations.  
[Self-Hosted Matomo Web Analytics on AWS: How We Enhanced Our Shopify Analytics Stack and Cut Marketing Tool Costs](https://medium.com/@dan.jam.kuhn/self-hosted-matomo-web-analytics-on-aws-how-we-enhanced-our-shopify-analytics-stack-and-cut-3476526132a8)


[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS CDK](https://img.shields.io/badge/AWS%20CDK-v2.165.0-orange)](https://aws.amazon.com/cdk/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-blue)](https://www.python.org/)

## 🚀 Quick Start

Deploy Matomo on AWS in 3 simple steps:

### Option 1: Using Make (Recommended)
```bash
# 1. Clone and configure
git clone <this-repo>
cd matomo-aws-server

# 2. Complete deployment with validation
make fresh-deploy

# 3. Access Matomo at the provided URL
```

### Option 2: Using Scripts Directly
```bash
# 1. Clone and configure
git clone <this-repo>
cd matomo-aws-server

# 2. Run one-time setup
./scripts/setup.sh

# 3. Deploy to AWS
./scripts/deploy.sh

# 4. Access Matomo at the provided URL
```

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Architecture](#-architecture)
- [Configuration](#-configuration)
- [Deployment](#-deployment)
- [Usage](#-usage)
- [Makefile Commands](#%EF%B8%8F-makefile-commands)
- [Available Scripts](#%EF%B8%8F-available-scripts)
- [Security](#-security)
- [Costs](#-costs)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

## ✨ Features

### 🏗️ Infrastructure
- **Multi-stack CDK architecture** - Separate networking, database, and compute
- **Cost-optimized deployment** - Single AZ, minimal resources, free tier eligible
- **RDS MySQL Database** - Managed MySQL database with automatic backups
- **Secure by default** - Private subnets, security groups, encrypted secrets

### 🔐 Security
- **SSH keys in Parameter Store** - No local key files to manage
- **Database credentials in Secrets Manager** - Auto-generated secure passwords
- **IAM least privilege** - Minimal permissions for all resources
- **VPC isolation** - Private database subnets, controlled access

### 🛠️ Automation
- **Two-step deployment** - `./scripts/setup.sh` (once) then `./scripts/deploy.sh` (deploy/test cycles)
- **Automatic Matomo installation** - Fully configured on first boot
- **Easy cleanup** - `./scripts/destroy.sh` removes everything
- **Connection details** - `./scripts/get-info.sh` shows all access info
- **Cross-platform** - Linux/macOS native, Windows via WSL2

### ⚠️ What This Project Does NOT Include

This project focuses on core infrastructure deployment. **You will need to configure separately**:

- 🌍 **Domain Name / DNS** - Point your domain to the EC2 instance
- 🔒 **SSL Certificates** - Set up HTTPS with Let's Encrypt, ACM, or your own certs  
- 📧 **Email Configuration** - SMTP settings for Matomo notifications
- 🔄 **Load Balancing** - For high-availability deployments
- 📊 **Advanced Monitoring** - CloudWatch dashboards, alerting
- 🔐 **WAF / DDoS Protection** - Additional security layers

**This keeps the project simple and focused** while giving you flexibility to add these components as needed.

## 📋 Prerequisites

### Required Tools
- **AWS CLI** - [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **AWS CDK** - `npm install -g aws-cdk`
- **Python 3.8+** - [Download](https://www.python.org/downloads/)
- **Git** - [Install Guide](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

### AWS Setup
```bash
# Configure AWS credentials
aws configure

# Verify access
aws sts get-caller-identity
```

### 🪟 Windows Users

This project uses Bash scripts that don't run natively on Windows. **We recommend using WSL (Windows Subsystem for Linux)** for the best experience:

#### **Option 1: WSL2 (Recommended)**
```powershell
# Install WSL2 with Ubuntu (run as Administrator)
wsl --install

# Restart your computer when prompted

# Access your project files in WSL
wsl
cd /mnt/c/path/to/your/project/matomo-aws-server

# Install tools in WSL Ubuntu environment
sudo apt update
sudo apt install python3 python3-pip nodejs npm git

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install CDK
sudo npm install -g aws-cdk

# Configure AWS (your Windows AWS credentials work in WSL)
aws configure

# Use project normally
./scripts/deploy.sh
```

#### **Option 2: Manual Deployment (PowerShell)**
If you prefer not to use WSL, you can deploy manually:
```powershell
# Install Python, Node.js, AWS CLI, and CDK on Windows first
# Then in PowerShell:

python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt

# Deploy manually
cdk bootstrap
cdk deploy --all

# Get deployment info
aws cloudformation describe-stacks --stack-name matomo-analytics-compute --query "Stacks[0].Outputs"
```

#### **WSL Benefits:**
- ✅ All scripts work exactly as documented
- ✅ No modifications needed
- ✅ Same experience as macOS/Linux
- ✅ Full compatibility with project instructions

### 🐧 Linux Users

**Excellent news!** This project has **native Linux support** with no modifications needed. Linux compatibility is actually better than macOS since most tools are designed for Linux first.

#### **Ubuntu/Debian Setup:**
```bash
# Install required tools
sudo apt update
sudo apt install python3 python3-pip python3-venv nodejs npm git curl unzip

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Install CDK
sudo npm install -g aws-cdk

# Configure AWS and deploy
aws configure
./scripts/deploy.sh
```

#### **RHEL/CentOS/Fedora:**
```bash
# Replace 'apt' with 'dnf' (or 'yum' for older versions)
sudo dnf install python3 python3-pip nodejs npm git curl unzip
# Then follow AWS CLI and CDK installation above
```

#### **Linux Advantages:**
- ✅ **Native Bash support** - All scripts work perfectly
- ✅ **Package managers** - Easy dependency installation  
- ✅ **No compatibility issues** - Everything runs natively
- ✅ **Container-ready** - Perfect for CI/CD pipelines

### Permissions Required
Your AWS user/role needs these permissions:
- CloudFormation (full access)
- EC2 (full access)
- VPC (full access)
- IAM (create/manage roles)
- RDS (if using database)
- Secrets Manager (if using database)
- Systems Manager Parameter Store

## 🏗️ Architecture

### Infrastructure Components

```
┌─────────────────────────────────────────────────────────┐
│                    AWS Region                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │                     VPC                            │ │
│  │  ┌─────────────┐    ┌──────────────────────────────┐ │ │
│  │  │   Public    │    │         Private              │ │ │
│  │  │   Subnet    │    │        Subnet                │ │ │
│  │  │             │    │                              │ │ │
│  │  │ ┌─────────┐ │    │  ┌─────────────────────────┐ │ │ │
│  │  │ │   EC2   │ │    │  │      RDS MySQL          │ │ │ │
│  │  │ │ Matomo  │ │    │  │    (Optional)           │ │ │ │
│  │  │ │ Server  │ │    │  │                         │ │ │ │
│  │  │ └─────────┘ │    │  └─────────────────────────┘ │ │ │
│  │  └─────────────┘    └──────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Stack Organization
1. **NetworkingStack** - VPC, subnets, security groups, NAT gateway
2. **DatabaseStack** - RDS MySQL, subnet group, secrets (optional)
3. **ComputeStack** - EC2 instance, IAM roles, user data script

### Cost Optimization
- **Single AZ deployment** - Reduces cross-AZ charges
- **t3.micro instances** - Free tier eligible
- **Minimal storage** - 20GB RDS, 8GB EC2
- **Single NAT Gateway** - Shared across subnets
- **No backups by default** - Reduces RDS costs

## ⚙️ Configuration

Configuration is managed via `cdk.json` context:

### Basic Configuration
```json
{
  "context": {
    "matomo": {
      "projectName": "matomo-analytics",
      "enableDatabase": false,
      "costOptimized": true,
      "instanceType": "t3.micro",
      "allowedSshCidr": "0.0.0.0/0"
    }
  }
}
```

### Database Configuration
```json
{
  "context": {
    "matomo": {
      "enableDatabase": true,
      "databaseConfig": {
        "instanceClass": "db.t3.micro",
        "allocatedStorage": 20,
        "multiAZ": false,
        "backupRetention": 0
      }
    }
  }
}
```

### Network Configuration
```json
{
  "context": {
    "matomo": {
      "networking": {
        "singleNatGateway": true,
        "enableVpcEndpoints": false,
        "vpcCidr": "10.0.0.0/16"
      }
    }
  }
}
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `projectName` | `matomo-analytics` | Prefix for all AWS resources |
| `enableDatabase` | `false` | Deploy RDS MySQL instance |
| `costOptimized` | `true` | Use single AZ, minimal resources |
| `instanceType` | `t3.micro` | EC2 instance type |
| `allowedSshCidr` | `0.0.0.0/0` | IP range allowed SSH access |

## 🚀 Deployment

### Method 1: Using Makefile (Recommended)
```bash
# Clone the repository
git clone <this-repo>
cd matomo-aws-server

# Complete deployment with validation
make fresh-deploy
```

**Makefile Benefits:**
- **Single command deployment** - Everything automated
- **Built-in validation** - Automatic post-deployment checks
- **Better error handling** - Intelligent retry and wait logic
- **Convenient workflows** - Common tasks simplified

### Method 2: Using Scripts Directly
```bash
# Clone the repository
git clone <this-repo>
cd matomo-aws-server

# Step 1: One-time setup (prerequisites, dependencies, CDK bootstrap)
./scripts/setup.sh

# Step 2: Deploy to AWS (repeat for updates)
./scripts/deploy.sh
```

**Two-Script Design Benefits:**
- **Faster iterations** - Skip setup after initial run
- **Clear workflow** - Setup once, deploy repeatedly
- **Better debugging** - Separate setup vs deployment issues

#### Setup Script (`./scripts/setup.sh`) handles:
- ✅ Check prerequisites (AWS CLI, CDK, Python)
- ✅ Verify AWS credentials
- ✅ Create virtual environment & install dependencies
- ✅ Bootstrap CDK (one-time AWS setup)

#### Deploy Script (`./scripts/deploy.sh`) handles:
- ✅ Deploy all CDK stacks
- ✅ Display connection information

### Method 3: Manual Deployment
```bash
# Install dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy all stacks
cdk deploy --all
```

### Deployment Options

#### Deploy with Database
```bash
# Edit cdk.json to enable database
sed -i '' 's/"enableDatabase": false/"enableDatabase": true/' cdk.json

# Setup (if not done already)
./scripts/setup.sh

# Deploy
./scripts/deploy.sh
```

#### Deploy Specific Stacks
```bash
# Deploy only networking
cdk deploy matomo-analytics-networking

# Deploy networking and compute (no database)
cdk deploy matomo-analytics-networking matomo-analytics-compute
```

## 📖 Usage

### Accessing Matomo

After deployment, you'll receive:
- 🌐 **Matomo URL**: `http://YOUR-EC2-IP`
- 🔐 **SSH Access**: Command to connect to the server
- 🗄️ **Database Info**: Connection details (if RDS enabled)

### Getting Connection Information
```bash
# View all deployment details
./scripts/get-info.sh

# Get database password specifically
./scripts/get-db-password.sh

# Get just the SSH command
cdk outputs | grep SshCommand
```

### SSH Access
```bash
# The get-info script automatically retrieves your SSH key
./scripts/get-info.sh

# Then connect using the provided command
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
```

### Database Credentials
When RDS MySQL is enabled, database credentials are automatically generated and stored securely:

```bash
# Get database username and password
./scripts/get-db-password.sh

# Alternative: Manual retrieval using AWS CLI
SECRET_ARN=$(aws cloudformation describe-stacks --stack-name matomo-analytics-database --query "Stacks[0].Outputs[?OutputKey=='DatabaseSecretArn'].OutputValue" --output text)
aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query 'SecretString' --output text | python -c "import sys, json; data=json.load(sys.stdin); print(f'Username: {data[\"username\"]}'); print(f'Password: {data[\"password\"]}')"
```

### Matomo Setup

1. **Access the web interface** at the provided URL
2. **Complete the installation wizard**:
   - Database: Use provided RDS MySQL connection details
   - Admin user: Create your admin account
   - Website: Add your first website to track
3. **Install the tracking code** on your website

### ⚠️ Important: DNS and SSL Setup Required

**This project deploys Matomo with HTTP only** and provides a public IP address. For production use, you'll need to configure:

#### 🌍 Domain Name Setup
1. **Point your domain** to the EC2 instance public IP:
   ```bash
   # Example DNS A record
   analytics.yourdomain.com → YOUR-EC2-PUBLIC-IP
   ```

2. **Update Matomo trusted hosts** in `/var/www/html/config/config.ini.php`:
   ```ini
   [General]
   trusted_hosts[] = "analytics.yourdomain.com"
   ```

#### 🔒 SSL Certificate Setup
1. **Install Let's Encrypt** (recommended for free SSL):
   ```bash
   sudo dnf install certbot python3-certbot-apache
   sudo certbot --apache -d analytics.yourdomain.com
   ```

2. **Or use AWS Certificate Manager** with Application Load Balancer
3. **Or bring your own certificate** and configure Apache SSL

#### 🛡️ Security Considerations
- **Never use HTTP in production** - Always configure SSL/TLS
- **Update trusted hosts** to prevent HTTP Host header attacks
- **Consider AWS WAF** for additional protection
- **Set up monitoring** and backup strategies

### Post-Deployment Validation

After deployment, use the validation scripts to ensure everything is working correctly:

```bash
# 1. Validate AWS infrastructure
./scripts/validate-infrastructure.sh

# 2. Validate Matomo installation (single check)
./scripts/validate-matomo.sh

# 3. Wait for Matomo installation to complete (for fresh deployments)
./scripts/validate-matomo.sh --wait

```

#### Validation Features

**Infrastructure Validation (`validate-infrastructure.sh`)**:
- ✅ Verifies VPC, subnets, and security groups
- ✅ Checks EC2 instance status and configuration
- ✅ Validates RDS instance status and AWS resources (if enabled)
- ✅ Tests security group rules and access restrictions
- ✅ Validates database credentials in Secrets Manager
- ℹ️ **Note**: Database is in private subnets (not publicly accessible - this is correct)

**Matomo Installation Validation (`validate-matomo.sh`)**:
- ✅ Tests HTTP connectivity to Matomo URL
- ✅ Validates web interface response and content
- ✅ Detects installation wizard vs. completed setup
- ✅ Checks SSL/HTTPS configuration
- ✅ **Wait mode**: Monitors installation progress with intelligent retry
- ✅ **Timeout control**: Configurable wait time (default: 15 minutes)

```bash
# Basic validation (single check)
./scripts/validate-matomo.sh

# Wait for installation to complete
./scripts/validate-matomo.sh --wait

# Custom timeout (30 minutes)
./scripts/validate-matomo.sh --wait --timeout 1800

# Custom retry interval (60 seconds)
./scripts/validate-matomo.sh --wait --interval 60
```


### Manual Installation Monitoring
```bash
# SSH into the server and check logs
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP

# View installation logs
sudo tail -f /var/log/matomo-install.log

# Check installation status
cat /var/www/html/INSTALLATION_STATUS
```

## 🔐 Security

This deployment follows AWS security best practices:

### Credentials Management
- **SSH Keys**: Stored in AWS Systems Manager Parameter Store (encrypted)
- **Database Passwords**: Auto-generated and stored in AWS Secrets Manager
- **No Local Secrets**: All sensitive data managed by AWS services

### Network Security
- **Private Database**: RDS deployed in private subnets only
- **Security Groups**: Minimal required access (HTTP, HTTPS, SSH)
- **VPC Isolation**: Complete network isolation from other AWS resources

### Access Control
- **IAM Roles**: Least privilege access for EC2 instance
- **SSH Access**: Configurable IP ranges (default allows all - change this!)
- **Database Access**: Only from EC2 security group

### Security Recommendations
- [ ] Restrict SSH access to your IP: Update `allowedSshCidr` in `cdk.json`
- [ ] Enable database backups: Set `backupRetention > 0` for production
- [ ] Configure Matomo trusted hosts: Edit `/var/www/html/config/config.ini.php`
- [ ] Set up SSL/TLS: Use ALB with ACM certificate (not included)

For detailed security information, see [SECURITY.md](docs/SECURITY.md).

## 💰 Costs

### Cost Breakdown (Monthly, US-East-1)

| Component | Free Tier | Paid |
|-----------|-----------|------|
| EC2 t3.micro | $0 | $7.50 |
| RDS db.t3.micro | $0 | $12.50 |
| EBS Storage (28GB) | $0 | $2.80 |
| NAT Gateway | N/A | $32.00 |
| Data Transfer | 1GB free | $0.09/GB |

**Total Monthly Cost:**
- **With Free Tier**: ~$32 (NAT Gateway only) + $12-15 (RDS) = ~$45-50
- **Without Free Tier**: ~$55

### Cost Optimization Tips
- **Use existing VPC**: Skip NAT Gateway if you have one
- **Optimize database**: Use smaller RDS instances for development
- **Stop when not needed**: Stop EC2 instance to save compute costs
- **Use Spot Instances**: Modify the code for 60-90% savings

For detailed cost information, see [COSTS.md](docs/COSTS.md).

## 🛠️ Makefile Commands

This project includes a comprehensive Makefile that wraps all scripts with convenient commands:

### Quick Reference

```bash
# Get help and see all available commands
make help

# Common workflows
make fresh-deploy          # Complete first-time deployment
make quick-deploy           # Quick deployment (setup already done)
make redeploy              # Redeploy after changes
make check                 # Validate everything is working

# Information and status
make info                  # Get deployment details
make status                # Alias for info
make password              # Get database credentials

# Validation
make validate              # Run all validation checks
make validate-all          # Run all validation with wait mode
make validate-matomo-wait  # Wait for Matomo installation

# Cleanup
make clean                 # Interactive cleanup
make clean-force           # Automated cleanup (no prompts)

# Advanced
make ssh                   # Connect to EC2 instance
make logs                  # View installation logs
make open                  # Open Matomo in browser
make diff                  # Preview changes
```

### Available Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands with descriptions |
| `make setup` | Run one-time setup (prerequisites, dependencies, CDK bootstrap) |
| `make deploy` | Deploy Matomo infrastructure to AWS |
| `make info` | Get all deployment information (IP, SSH, database details) |
| `make password` | Get database username and password |
| `make validate-infrastructure` | Validate AWS infrastructure |
| `make validate-matomo` | Validate Matomo installation (single check) |
| `make validate-matomo-wait` | Wait for Matomo installation to complete |
| `make validate` | Run all validation checks |
| `make validate-all` | Run all validation checks with wait mode |
| `make clean` | Remove all AWS resources (interactive) |
| `make clean-force` | Remove all AWS resources (no prompts) |
| `make ssh` | Connect to EC2 instance via SSH |
| `make logs` | View Matomo installation logs |
| `make open` | Open Matomo URL in browser |
| `make diff` | Preview deployment changes |
| `make version` | Show tool versions and AWS account info |

### Workflow Examples

```bash
# First-time deployment
make fresh-deploy

# Daily development workflow
make diff                  # Preview changes
make redeploy             # Deploy changes
make check                # Verify everything works

# Troubleshooting
make validate-infrastructure  # Check AWS resources
make validate-matomo-wait    # Wait for installation
make logs                    # View installation logs
make ssh                     # Connect to debug

# Cleanup
make clean                # Interactive cleanup
make clean-force          # For CI/CD automation
```

## 🛠️ Available Scripts

For users who prefer direct script usage, this project includes several utility scripts:

| Script | Purpose | Usage |
|--------|---------|--------|
| `./scripts/setup.sh` | **Setup** - One-time setup (prerequisites, dependencies, CDK bootstrap) | `./scripts/setup.sh` |
| `./scripts/deploy.sh` | **Deploy** - Deploy stacks to AWS | `./scripts/deploy.sh` |
| `./scripts/get-info.sh` | **Info** - Get all deployment details | `./scripts/get-info.sh` |
| `./scripts/get-db-password.sh` | **Password** - Get database credentials | `./scripts/get-db-password.sh` |
| `./scripts/validate-infrastructure.sh` | **Validate** - Verify AWS infrastructure | `./scripts/validate-infrastructure.sh` |
| `./scripts/validate-matomo.sh` | **Validate** - Check Matomo installation | `./scripts/validate-matomo.sh [--wait]` |
| `./scripts/destroy.sh` | **Destroy** - Remove all AWS resources | `./scripts/destroy.sh [--force]` |

### Script Details

```bash
# 🛠️ One-time setup (run first)
./scripts/setup.sh

# 🚀 Deploy to AWS (after setup)
./scripts/deploy.sh

# 📊 View all deployment information
./scripts/get-info.sh

# 🔐 Get database username and password
./scripts/get-db-password.sh

# ✅ Validate infrastructure (VPC, security groups, EC2, RDS)
./scripts/validate-infrastructure.sh

# ✅ Validate Matomo installation (web interface)
./scripts/validate-matomo.sh

# ✅ Wait for Matomo installation to complete (with timeout)
./scripts/validate-matomo.sh --wait --timeout 1800


# 🧹 Complete cleanup with confirmation
./scripts/destroy.sh

# 🧹 Force cleanup without prompts (for automation)
./scripts/destroy.sh --force
```

## 🧹 Cleanup

### Complete Cleanup

```bash
# Interactive cleanup (with confirmation)
./scripts/destroy.sh

# Force cleanup without prompts (for automation)
./scripts/destroy.sh --force
```

#### Cleanup Options

**Interactive Mode (Default)**:
- Shows detailed deletion plan
- Requires typing "DELETE" to confirm
- 5-second countdown before proceeding
- Safe for manual use

**Force Mode (`--force` or `-f`)**:
- Shows deletion plan but skips confirmation
- No prompts or countdowns
- Perfect for automation/CI-CD
- Use with caution!

```bash
# Examples
./scripts/destroy.sh                    # Interactive confirmation
./scripts/destroy.sh --force            # Skip all prompts  
./scripts/destroy.sh -f                 # Short form
./scripts/destroy.sh --help             # Show usage
```

Both modes will:
- ⚠️ **Permanently delete** all AWS resources
- ⚠️ **Delete all data** (Matomo database, analytics data)
- ✅ Stop all ongoing charges
- ✅ Clean up local files

### Partial Cleanup
```bash
# Remove only specific stacks
cdk destroy matomo-analytics-compute
cdk destroy matomo-analytics-database
cdk destroy matomo-analytics-networking
```

## 🛠️ Troubleshooting

### Common Issues

#### Scripts Don't Work on Windows
```bash
# Error: './scripts/deploy.sh' is not recognized...
# Solution: Use WSL2 (recommended)
wsl --install
wsl
cd /mnt/c/path/to/matomo-aws-server
./scripts/deploy.sh

# Alternative: Deploy manually with PowerShell
python -m venv venv
venv\Scripts\activate
cdk deploy --all
```

#### Deployment Fails
```bash
# Check CDK bootstrap status
cdk bootstrap --show-template

# Verify AWS credentials
aws sts get-caller-identity

# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name matomo-analytics-networking
```

#### Can't Access Matomo
```bash
# Use validation scripts to diagnose issues
./scripts/validate-infrastructure.sh     # Check AWS resources
./scripts/validate-matomo.sh --wait      # Wait for installation
```

- Wait 10-15 minutes for installation to complete
- Check security group allows HTTP (port 80)
- Verify EC2 instance is running
- Check installation logs on the server

#### SSH Connection Fails
- Verify SSH key retrieved: `./scripts/get-info.sh`
- Check security group allows SSH (port 22)
- Ensure correct IP address and key file permissions

For more troubleshooting help, see [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## 📚 Additional Documentation

- [Security Guide](docs/SECURITY.md) - Detailed security considerations
- [Cost Optimization](docs/COSTS.md) - Advanced cost optimization strategies  
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [Matomo Analytics Examples](docs/MATOMO_ANALYTICS_EXAMPLES.md) - SQL queries for e-commerce analytics with Matomo
- [Advanced Analytics Documentation](docs/matomo-advanced-analytics-documentation.md) - Comprehensive guide to advanced Matomo SQL queries
- [Advanced Analytics SQL File](docs/matomo-advanced-analytics-examples.sql) - Complete SQL query collection

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Matomo](https://matomo.org/) - The open-source web analytics platform
- [AWS CDK](https://aws.amazon.com/cdk/) - Infrastructure as Code framework
- Original inspiration from personal client project

---

**Questions?** Open an issue or check the [documentation](docs/) directory.

**Need help?** See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common solutions.
