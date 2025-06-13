# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the Matomo AWS Server deployment.

## 🚨 Quick Diagnostics

### Health Check Commands
```bash
# Check deployment status
./scripts/get-info.sh

# Verify AWS credentials
aws sts get-caller-identity

# Check CDK status
cdk list

# Test connectivity
ping YOUR-EC2-IP
curl -I http://YOUR-EC2-IP
```

## 🛠️ Deployment Issues

### CDK Bootstrap Failures

#### Problem: "CDK is not bootstrapped in this region"
```
Error: Need to perform AWS CDK bootstrap in region us-east-1
```

**Solution:**
```bash
# Bootstrap CDK in your region
cdk bootstrap aws://ACCOUNT-ID/REGION

# If unsure of account/region:
aws sts get-caller-identity
aws configure get region
```

#### Problem: "Insufficient permissions for bootstrap"
```
Error: User is not authorized to perform: iam:CreateRole
```

**Solution:**
```bash
# Verify required permissions
aws iam get-user
aws iam list-attached-user-policies --user-name YOUR-USERNAME

# Required policies:
# - AdministratorAccess (or equivalent CDK permissions)
```

### Stack Deployment Failures

#### Problem: "Stack already exists"
```
Error: Stack matomo-analytics-networking already exists
```

**Solution:**
```bash
# Check existing stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE

# Update existing stack
cdk deploy --force

# Or destroy and recreate
cdk destroy matomo-analytics-networking
cdk deploy matomo-analytics-networking
```

#### Problem: "Resource limit exceeded"
```
Error: The maximum number of VPCs has been reached
```

**Solution:**
```bash
# Check VPC limits
aws ec2 describe-vpcs --query 'length(Vpcs)'
aws service-quotas get-service-quota --service-code ec2 --quota-code L-F678F1CE

# Delete unused VPCs or request limit increase
aws support create-case --subject "VPC Limit Increase"
```

#### Problem: "Availability Zone capacity issues"
```
Error: Insufficient capacity in Availability Zone us-east-1a
```

**Solution:**
```bash
# Modify cdk.json to use different AZ
{
  "context": {
    "matomo": {
      "networking": {
        "preferredAz": "us-east-1b"
      }
    }
  }
}

# Or enable multi-AZ
{
  "context": {
    "matomo": {
      "costOptimized": false
    }
  }
}
```

### Dependency Issues

#### Problem: "Python module not found"
```
ModuleNotFoundError: No module named 'aws_cdk'
```

**Solution:**
```bash
# Activate virtual environment
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# If venv doesn't exist
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### Problem: "CDK version mismatch"
```
Error: CDK version mismatch. Found 2.140.0, expected 2.145.0
```

**Solution:**
```bash
# Update CDK globally
npm update -g aws-cdk

# Or install specific version
npm install -g aws-cdk@2.145.0

# Verify version
cdk --version
```

## 🌐 Connectivity Issues

### Cannot Access Matomo Web Interface

#### Problem: "Connection timed out"
```bash
curl: (7) Failed to connect to 12.34.56.78 port 80: Connection timed out
```

**Diagnosis:**
```bash
# Check instance status
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# Check security groups
aws ec2 describe-security-groups --group-ids sg-1234567890abcdef0

# Verify Matomo installation
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
sudo systemctl status httpd
sudo tail -f /var/log/matomo-install.log
```

**Solutions:**

1. **Wait for installation** (3-5 minutes after deployment)
2. **Check security group rules**:
   ```bash
   # Should allow port 80 from 0.0.0.0/0
   aws ec2 authorize-security-group-ingress \
     --group-id sg-1234567890abcdef0 \
     --protocol tcp \
     --port 80 \
     --cidr 0.0.0.0/0
   ```
3. **Restart Apache**:
   ```bash
   ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
   sudo systemctl restart httpd
   sudo systemctl enable httpd
   ```

#### Problem: "502 Bad Gateway" or "Service Unavailable"

**Diagnosis:**
```bash
# SSH to server and check services
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP

# Check Apache status
sudo systemctl status httpd
sudo journalctl -u httpd -f

# Check PHP status
php -v
sudo systemctl status php-fpm

# Check Matomo installation
ls -la /var/www/html/
cat /var/www/html/INSTALLATION_STATUS
```

**Solutions:**

1. **Restart services**:
   ```bash
   sudo systemctl restart httpd
   sudo systemctl restart php-fpm
   ```

2. **Check PHP configuration**:
   ```bash
   # Verify PHP modules
   php -m | grep -E "(mysql|gd|xml|mbstring)"
   
   # Check PHP errors
   sudo tail -f /var/log/php_errors.log
   ```

3. **Fix file permissions**:
   ```bash
   sudo chown -R apache:apache /var/www/html/
   sudo chmod -R 755 /var/www/html/
   sudo chmod -R 777 /var/www/html/tmp/
   sudo chmod -R 777 /var/www/html/config/
   ```

### SSH Connection Issues

#### Problem: "Permission denied (publickey)"
```bash
Permission denied (publickey).
```

**Solutions:**

1. **Retrieve SSH key properly**:
   ```bash
   ./scripts/get-info.sh
   chmod 400 matomo-key.pem
   ```

2. **Manual key retrieval**:
   ```bash
   aws ssm get-parameter \
     --name "/matomo/ec2/private-key/matomo-keypair" \
     --with-decryption \
     --query 'Parameter.Value' \
     --output text > matomo-key.pem
   chmod 400 matomo-key.pem
   ```

3. **Verify SSH command**:
   ```bash
   ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
   # NOT: ssh -i matomo-key.pem root@YOUR-EC2-IP
   ```

#### Problem: "Host key verification failed"
```bash
Host key verification failed.
```

**Solution:**
```bash
# Remove old host key and retry
ssh-keygen -R YOUR-EC2-IP
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
```

## 🗄️ Database Issues

### RDS Connection Problems

#### Problem: "Can't connect to MySQL server"

**Diagnosis:**
```bash
# SSH to EC2 and test database connection
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP

# Get database credentials
aws secretsmanager get-secret-value \
  --secret-id YOUR-SECRET-ARN \
  --query 'SecretString' \
  --output text

# Test connection
mysql -h YOUR-RDS-ENDPOINT -u matomo -p
```

**Solutions:**

1. **Check security groups**:
   ```bash
   # Database SG should allow port 3306 from web SG
   aws ec2 describe-security-groups --group-ids sg-database
   ```

2. **Verify RDS status**:
   ```bash
   aws rds describe-db-instances --db-instance-identifier matomo-database
   ```

3. **Check network connectivity**:
   ```bash
   # From EC2 instance
   telnet YOUR-RDS-ENDPOINT 3306
   nslookup YOUR-RDS-ENDPOINT
   ```

#### Problem: "Access denied for user 'matomo'"

**Solutions:**

1. **Reset database password**:
   ```bash
   # Generate new password in Secrets Manager
   aws secretsmanager update-secret \
     --secret-id YOUR-SECRET-ARN \
     --generate-secret-string \
     --secret-string-template '{"username":"matomo"}' \
     --generate-string-key "password"
   ```

2. **Update Matomo configuration**:
   ```bash
   # SSH to server and update config
   sudo nano /var/www/html/config/config.ini.php
   # Update password in [database] section
   ```

### Database Connection Verification

#### Problem: "Database connection intermittent"

**Solutions:**

1. **Check RDS instance status**:
   ```bash
   aws rds describe-db-instances --db-instance-identifier matomo-database
   ```

2. **Verify security group rules**:
   ```bash
   # Database should allow port 3306 from EC2 security group
   aws ec2 describe-security-groups --group-ids sg-database
   ```

3. **Test connectivity from EC2**:
   ```bash
   ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
   mysql -h YOUR-RDS-ENDPOINT -u matomo -p
   ```

## 🔧 Performance Issues

### High Memory Usage

#### Problem: "Out of memory" errors

**Diagnosis:**
```bash
# Check memory usage
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP
free -h
top
htop  # if available
```

**Solutions:**

1. **Increase instance size**:
   ```json
   // Update cdk.json
   {
     "context": {
       "matomo": {
         "instanceType": "t3.small"  // or larger
       }
     }
   }
   ```

2. **Optimize PHP settings**:
   ```bash
   sudo nano /etc/php.ini
   # Increase:
   memory_limit = 512M
   max_execution_time = 300
   ```

3. **Add swap space**:
   ```bash
   # Create 1GB swap file
   sudo fallocate -l 1G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   
   # Make permanent
   echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
   ```

### Slow Database Performance

#### Problem: "Database queries taking too long"

**Solutions:**

1. **Upgrade RDS instance**:
   ```json
   // Update cdk.json
   {
     "context": {
       "matomo": {
         "databaseConfig": {
           "instanceClass": "db.t3.small"
         }
       }
     }
   }
   ```

2. **Enable query optimization**:
   ```sql
   -- Connect to database and run:
   SHOW PROCESSLIST;
   EXPLAIN SELECT * FROM matomo_log_visit LIMIT 10;
   ```

3. **Archive old data**:
   ```bash
   # Setup Matomo archiving cron job
   echo "5 * * * * /usr/bin/php /var/www/html/console core:archive" | sudo crontab -
   ```

## 📊 Monitoring and Logs

### Log Locations

| Service | Log Location |
|---------|-------------|
| Matomo Install | `/var/log/matomo-install.log` |
| Apache Access | `/var/log/httpd/access_log` |
| Apache Error | `/var/log/httpd/error_log` |
| PHP Errors | `/var/log/php_errors.log` |
| System | `/var/log/messages` |
| SSH | `/var/log/secure` |

### Useful Log Commands

```bash
# Monitor logs in real-time
sudo tail -f /var/log/matomo-install.log
sudo tail -f /var/log/httpd/error_log

# Search for errors
sudo grep -i error /var/log/httpd/error_log
sudo grep -i "fatal\|error" /var/log/php_errors.log

# Check system logs
sudo journalctl -u httpd -f
sudo journalctl --since "1 hour ago"
```

## 🆘 Emergency Procedures

### Complete System Recovery

#### If everything is broken:

1. **Stop the stack**:
   ```bash
   aws ec2 stop-instances --instance-ids i-1234567890abcdef0
   ```

2. **Create snapshot**:
   ```bash
   aws ec2 create-snapshot \
     --volume-id vol-1234567890abcdef0 \
     --description "Emergency backup"
   ```

3. **Redeploy from scratch**:
   ```bash
   ./scripts/cleanup.sh
   ./scripts/deploy.sh
   ```

### Data Recovery

#### Restore from RDS snapshot:
```bash
# List available snapshots
aws rds describe-db-snapshots --db-instance-identifier matomo-database

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier matomo-database-restored \
  --db-snapshot-identifier snap-12345678
```

## 📞 Getting Help

### Support Resources

1. **AWS Documentation**: [docs.aws.amazon.com](https://docs.aws.amazon.com)
2. **Matomo Forums**: [forum.matomo.org](https://forum.matomo.org)
3. **CDK Documentation**: [docs.aws.amazon.com/cdk](https://docs.aws.amazon.com/cdk)

### Reporting Issues

When reporting issues, include:

1. **Error messages** (full text)
2. **Log outputs** (relevant sections)
3. **AWS region** and account details
4. **Configuration** (cdk.json context)
5. **Steps to reproduce**

### Diagnostic Information Collection

```bash
# Collect system information
./scripts/get-info.sh > system-info.txt

# Collect logs
ssh -i matomo-key.pem ec2-user@YOUR-EC2-IP "sudo journalctl --since '1 hour ago'" > system-logs.txt

# Collect CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name matomo-analytics-compute > cf-events.json
```

---

**Still having issues?** Check the [main README](../README.md) or create an issue with the diagnostic information above.