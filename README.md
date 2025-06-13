# Matomo AWS Server

Deploy Matomo web analytics on AWS EC2 with CDK - cost-optimized and production-ready.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS CDK](https://img.shields.io/badge/AWS%20CDK-v2.165.0-orange)](https://aws.amazon.com/cdk/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-blue)](https://www.python.org/)

## 🚀 Quick Start

Deploy Matomo on AWS in 3 simple steps:

```bash
# 1. Clone and configure
git clone <this-repo>
cd matomo-aws-server

# 2. Deploy everything
./scripts/deploy.sh

# 3. Access Matomo at the provided URL
```

**Total deployment time:** ~5-10 minutes  
**Monthly cost:** $32-55 (depending on free tier eligibility)

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Architecture](#-architecture)
- [Configuration](#-configuration)
- [Deployment](#-deployment)
- [Usage](#-usage)
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
- **One-command deployment** - `./scripts/deploy.sh`
- **Automatic Matomo installation** - Fully configured on first boot
- **Easy cleanup** - `./scripts/cleanup.sh` removes everything
- **Connection details** - `./scripts/get-info.sh` shows all access info

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

### Method 1: Automated Deployment (Recommended)
```bash
# Clone the repository
git clone <this-repo>
cd matomo-aws-server

# Deploy with automation script (handles virtual environment automatically)
./scripts/deploy.sh
```

**Note**: The script automatically detects and uses your existing virtual environment if present, or creates one if needed.

The script will:
- ✅ Check prerequisites
- ✅ Install dependencies
- ✅ Bootstrap CDK
- ✅ Deploy all stacks
- ✅ Display connection information

### Method 2: Manual Deployment
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

### Matomo Setup

1. **Access the web interface** at the provided URL
2. **Complete the installation wizard**:
   - Database: Use provided RDS MySQL connection details
   - Admin user: Create your admin account
   - Website: Add your first website to track
3. **Install the tracking code** on your website

### Monitoring Installation Progress
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

## 🧹 Cleanup

### Complete Cleanup
```bash
# Remove all AWS resources
./scripts/cleanup.sh
```

This will:
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
- Wait 3-5 minutes for installation to complete
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
