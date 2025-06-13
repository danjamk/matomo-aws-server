# Security Guide

This document provides detailed security considerations and best practices for the Matomo AWS Server deployment.

## 🔐 Security Overview

This deployment implements AWS security best practices with a defense-in-depth approach:

- **Zero local secrets** - All credentials managed by AWS services
- **Network isolation** - Private subnets and security groups
- **Least privilege access** - Minimal IAM permissions
- **Encrypted storage** - All data encrypted at rest and in transit

## 🏗️ Infrastructure Security

### Network Architecture

```
Internet Gateway
       │
   ┌───▼───┐
   │  NAT  │ (Public Subnet)
   │Gateway│
   └───┬───┘
       │
┌──────▼──────┐    ┌─────────────────┐
│    EC2      │    │   RDS MySQL     │
│   Matomo    │────│  (Private)      │
│  (Public)   │    │                 │
└─────────────┘    └─────────────────┘
```

**Security Boundaries:**
- **Public Subnet**: EC2 instance with controlled access
- **Private Subnet**: Database with no internet access
- **Security Groups**: Application-level firewall rules

### VPC Security

| Component | Security Feature |
|-----------|------------------|
| **VPC** | Isolated network (10.0.0.0/16) |
| **Public Subnet** | Internet access via IGW |
| **Private Subnet** | Internet access via NAT only |
| **Route Tables** | Controlled traffic routing |
| **Network ACLs** | Subnet-level access control |

### Security Groups

#### Web Security Group (EC2)
```yaml
Ingress Rules:
  - Port 22 (SSH): Configurable CIDR (default: 0.0.0.0/0)
  - Port 80 (HTTP): 0.0.0.0/0
  - Port 443 (HTTPS): 0.0.0.0/0

Egress Rules:
  - All traffic: 0.0.0.0/0
```

#### Database Security Group (RDS)
```yaml
Ingress Rules:
  - Port 3306 (MySQL): Web Security Group only

Egress Rules:
  - None (default deny)
```

## 🔑 Credentials Management

### SSH Key Management

**Storage**: AWS Systems Manager Parameter Store
- **Parameter Name**: `/matomo/ec2/private-key/{keypair-name}`
- **Type**: SecureString (encrypted with AWS KMS)
- **Access**: EC2 instance role only

**Retrieval**:
```bash
# Automated by get-info.sh script
aws ssm get-parameter \
  --name "/matomo/ec2/private-key/matomo-keypair" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > matomo-key.pem
```

### Database Credentials

**Storage**: AWS Secrets Manager
- **Format**: JSON with username/password
- **Encryption**: AWS KMS managed keys
- **Rotation**: Can be enabled for production

**Access Pattern**:
```python
# EC2 instance retrieves credentials
secret = secretsmanager.get_secret_value(SecretId=secret_arn)
credentials = json.loads(secret['SecretString'])
username = credentials['username']
password = credentials['password']
```

### IAM Security

#### EC2 Instance Role Permissions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/matomo/*"
    },
    {
      "Effect": "Allow", 
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:matomo-*"
    }
  ]
}
```

**Principle**: Least privilege access - only what's needed for operation.

## 🛡️ Application Security

### Matomo Security Configuration

#### Trusted Hosts
```php
# /var/www/html/config/config.ini.php
[General]
trusted_hosts[] = "your-domain.com"
trusted_hosts[] = "12.34.56.78"  # EC2 IP
```

#### Security Headers
```apache
# Recommended Apache configuration
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
```

### Database Security

#### MySQL Configuration
- **Default User**: `matomo` (non-root)
- **Network**: Private subnet only
- **Encryption**: At-rest encryption enabled
- **Backups**: Configurable (disabled by default for cost)

#### Connection Security
- **TLS**: Force encrypted connections
- **Authentication**: Strong auto-generated passwords
- **Access**: Limited to application security group

## 🚨 Security Monitoring

### CloudTrail Integration
```bash
# Monitor security-related API calls
aws logs filter-log-events \
  --log-group-name CloudTrail \
  --filter-pattern "{ $.eventName = GetSecretValue }"
```

### VPC Flow Logs
```bash
# Enable VPC flow logs for network monitoring
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-12345678 \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs
```

## ⚡ Security Recommendations

### Immediate Actions (High Priority)

#### 1. Restrict SSH Access
```json
// Update cdk.json
{
  "context": {
    "matomo": {
      "allowedSshCidr": "YOUR.IP.ADDRESS/32"
    }
  }
}
```

#### 2. Configure Trusted Hosts
```bash
# SSH to server and edit config
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
sudo nano /var/www/html/config/config.ini.php

# Add your domain/IP to trusted_hosts
[General]
trusted_hosts[] = "yourdomain.com"
```

#### 3. Enable Database Backups (Production)
```json
// Update cdk.json for production
{
  "context": {
    "matomo": {
      "databaseConfig": {
        "backupRetention": 7,
        "multiAZ": true
      }
    }
  }
}
```

### Enhanced Security (Production)

#### 1. SSL/TLS Implementation
```yaml
# Add Application Load Balancer with SSL
Resources:
  LoadBalancer:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Scheme: internet-facing
      SecurityGroups: [!Ref ALBSecurityGroup]
      
  SSLCertificate:
    Type: AWS::CertificateManager::Certificate
    Properties:
      DomainName: matomo.yourdomain.com
```

#### 2. WAF Protection
```yaml
# Web Application Firewall
Resources:
  WebACL:
    Type: AWS::WAFv2::WebACL
    Properties:
      Rules:
        - Name: AWSManagedRulesCommonRuleSet
          Priority: 1
          Statement:
            ManagedRuleGroupStatement:
              VendorName: AWS
              Name: AWSManagedRulesCommonRuleSet
```

#### 3. Security Groups Hardening
```python
# Restrict HTTP/HTTPS to ALB only
web_security_group.add_ingress_rule(
    peer=ec2.Peer.security_group_id(alb_security_group.security_group_id),
    connection=ec2.Port.tcp(80)
)
```

## 🔍 Security Auditing

### Regular Security Checks

#### 1. Access Review
```bash
# Review IAM roles and policies
aws iam list-attached-role-policies --role-name MatomoEC2Role

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-12345678
```

#### 2. Credential Rotation
```bash
# Rotate database credentials (if enabled)
aws secretsmanager rotate-secret --secret-id matomo-db-credentials

# Regenerate SSH keys
aws ec2 create-key-pair --key-name matomo-keypair-new
```

#### 3. Log Analysis
```bash
# Check for unauthorized access attempts
sudo grep "Failed password" /var/log/secure

# Monitor Matomo access logs
sudo tail -f /var/log/httpd/matomo_access.log
```

### Security Assessment Checklist

- [ ] SSH access restricted to known IPs
- [ ] Database in private subnet only
- [ ] Trusted hosts configured in Matomo
- [ ] SSL/TLS configured (production)
- [ ] Security groups follow least privilege
- [ ] CloudTrail logging enabled
- [ ] VPC Flow Logs enabled
- [ ] Regular security updates applied
- [ ] Backup and recovery tested
- [ ] Incident response plan documented

## 🚨 Incident Response

### Security Incident Procedures

#### 1. Suspected Compromise
```bash
# Immediately isolate the instance
aws ec2 modify-instance-attribute \
  --instance-id i-1234567890abcdef0 \
  --groups sg-emergency-isolation

# Create forensic snapshot
aws ec2 create-snapshot \
  --volume-id vol-1234567890abcdef0 \
  --description "Forensic snapshot - $(date)"
```

#### 2. Data Breach Response
1. **Isolate** affected systems
2. **Assess** scope of compromise
3. **Contain** the incident
4. **Eradicate** threats
5. **Recover** systems safely
6. **Document** lessons learned

#### 3. Key Rotation Emergency
```bash
# Emergency key rotation
aws secretsmanager update-secret \
  --secret-id matomo-db-credentials \
  --secret-string '{"username":"matomo","password":"NEW-SECURE-PASSWORD"}'

# Update application configuration
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
sudo systemctl restart httpd
```

## 📚 Security Resources

### AWS Security Best Practices
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/)
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [AWS Security Center](https://aws.amazon.com/security/)

### Matomo Security
- [Matomo Security Guide](https://matomo.org/docs/security/)
- [Matomo Hardening Guide](https://matomo.org/docs/security-how-to/)

### Security Tools
- [AWS Config](https://aws.amazon.com/config/) - Compliance monitoring
- [AWS GuardDuty](https://aws.amazon.com/guardduty/) - Threat detection
- [AWS Security Hub](https://aws.amazon.com/security-hub/) - Security posture management

---

**Remember**: Security is an ongoing process, not a one-time setup. Regularly review and update your security measures as threats evolve.