# Cost Optimization Guide

This guide provides detailed cost analysis and optimization strategies for the Matomo AWS Server deployment.

## 💰 Cost Overview

The Matomo AWS deployment is designed to be cost-effective while maintaining security and reliability. This guide helps you understand costs and optimize for your specific needs.

## 📊 Detailed Cost Breakdown

### Monthly Costs (US-East-1)

#### With Free Tier Eligibility
| Component | Hours/Month | Free Tier | Cost |
|-----------|-------------|-----------|------|
| **EC2 t3.micro** | 744 | 750 hours | **$0.00** |
| **RDS db.t3.micro** | 744 | 750 hours | **$0.00** |
| **EBS gp2 (8GB)** | 8 GB | 30 GB | **$0.00** |
| **EBS gp2 (20GB)** | 20 GB | 30 GB | **$0.00** |
| **Data Transfer Out** | ~1-5 GB | 1 GB | **$0.36-1.80** |
| **NAT Gateway** | 744 hours | None | **$32.40** |
| **NAT Data Processing** | ~1-5 GB | None | **$0.04-0.20** |

**Total with Free Tier: ~$32.80-34.40/month**

#### Without Free Tier
| Component | Hours/Month | Rate | Cost |
|-----------|-------------|------|------|
| **EC2 t3.micro** | 744 | $0.0104/hour | **$7.74** |
| **RDS db.t3.micro** | 744 | $0.017/hour | **$12.65** |
| **EBS gp2 (28GB total)** | 28 GB | $0.10/GB | **$2.80** |
| **Data Transfer Out** | ~5 GB | $0.09/GB | **$0.45** |
| **NAT Gateway** | 744 hours | $0.045/hour | **$33.48** |
| **NAT Data Processing** | ~5 GB | $0.045/GB | **$0.23** |

**Total without Free Tier: ~$57.35/month**

### Additional Costs (Optional)

| Service | Use Case | Monthly Cost |
|---------|----------|--------------|
| **Application Load Balancer** | SSL termination, HA | $16.20 + $0.008/LCU |
| **CloudWatch Logs** | Enhanced monitoring | $0.50/GB ingested |
| **Route 53** | Custom domain | $0.50/hosted zone |
| **ACM Certificate** | SSL/TLS | Free |
| **Backup Storage** | RDS snapshots | $0.095/GB |
| **Multi-AZ RDS** | High availability | ~2x database cost |

## 🎯 Cost Optimization Strategies

### 1. Free Tier Maximization

#### EC2 Optimization
```bash
# Use t3.micro consistently
{
  "context": {
    "matomo": {
      "instanceType": "t3.micro"
    }
  }
}

# Monitor free tier usage
aws ce get-usage-and-cost \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

#### RDS Optimization
```bash
# Use db.t3.micro for free tier
{
  "context": {
    "matomo": {
      "databaseConfig": {
        "instanceClass": "db.t3.micro",
        "allocatedStorage": 20,  # Stay within 20GB free tier
        "backupRetention": 0     # Disable backups to avoid charges
      }
    }
  }
}
```

### 2. Development vs Production Configurations

#### Development (Minimal Cost)
```json
{
  "context": {
    "matomo": {
      "enableDatabase": true,
      "costOptimized": true,
      "instanceType": "t3.micro",
      "databaseConfig": {
        "instanceClass": "db.t3.micro",
        "backupRetention": 0
      },
      "networking": {
        "singleNatGateway": true
      }
    }
  }
}
```
**Estimated Cost: $45/month (includes RDS MySQL)**

#### Staging (Balanced)
```json
{
  "context": {
    "matomo": {
      "enableDatabase": true,
      "costOptimized": true,
      "instanceType": "t3.small",
      "databaseConfig": {
        "instanceClass": "db.t3.micro",
        "multiAZ": false,
        "backupRetention": 1
      }
    }
  }
}
```
**Estimated Cost: $45-50/month**

#### Production (Optimized for Performance)
```json
{
  "context": {
    "matomo": {
      "enableDatabase": true,
      "costOptimized": false,
      "instanceType": "t3.medium",
      "databaseConfig": {
        "instanceClass": "db.t3.small",
        "multiAZ": true,
        "backupRetention": 7
      }
    }
  }
}
```
**Estimated Cost: $85-100/month**

### 3. Spot Instances for Development

#### Enable Spot Instances (60-90% savings)
```python
# In compute_stack.py, modify instance creation:
instance = ec2.Instance(
    self, "MatomoInstance",
    instance_type=ec2.InstanceType("t3.micro"),
    # Add spot instance configuration
    spot_price="0.005",  # Maximum price willing to pay
    # ... other configurations
)
```

**Potential Savings: $5-7/month → $0.50-1.50/month**

### 4. Storage Optimization

#### EBS Volume Optimization
```python
# Use gp3 for better price/performance
ec2.Volume(
    self, "MatomoVolume",
    availability_zone=instance.instance_availability_zone,
    size=cdk.Size.gibibytes(20),
    volume_type=ec2.EbsDeviceVolumeType.GP3,
    iops=3000,        # Baseline IOPS
    throughput=125    # Baseline throughput MB/s
)
```

#### Lifecycle Policies
```bash
# Implement log rotation to manage disk usage
sudo logrotate -f /etc/logrotate.d/matomo

# Clean up old files periodically
sudo find /var/log -name "*.log" -mtime +30 -delete
```

### 5. Network Cost Reduction

#### Eliminate NAT Gateway (Advanced)
```python
# Option 1: Use NAT Instance (cheaper)
nat_instance = ec2.NatProvider.instance(
    instance_type=ec2.InstanceType.of(
        ec2.InstanceClass.BURSTABLE3,
        ec2.InstanceSize.NANO
    )
)

vpc = ec2.Vpc(
    self, "MatomoVPC",
    nat_gateway_provider=nat_instance
)
```
**Savings: $32/month → $3-5/month**

#### Option 2: VPC Endpoints
```python
# Add VPC endpoints for AWS services
vpc.add_gateway_endpoint("S3Endpoint",
    service=ec2.GatewayVpcEndpointAwsService.S3
)

vpc.add_interface_endpoint("SecretsManagerEndpoint",
    service=ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER
)
```

### 6. Database Cost Optimization

#### RDS Instance Size Decision Matrix

| Use Case | Recommendation | Monthly Cost |
|----------|----------------|--------------|
| **Personal/Demo** | RDS db.t3.micro | $45-50 |
| **Small Business (<1000 visits/day)** | RDS db.t3.micro | $45-50 |
| **Medium Business (1k-10k visits/day)** | RDS db.t3.small | $65-70 |
| **Large Business (>10k visits/day)** | RDS db.t3.medium+ | $100+ |

#### RDS Reserved Instances
```bash
# For production, consider 1-year reserved instances
# Savings: ~20-40% on RDS costs

aws rds describe-reserved-db-instances-offerings \
  --db-instance-class db.t3.micro \
  --duration 31536000  # 1 year in seconds
```

### 7. Monitoring and Alerting

#### Cost Monitoring Setup
```bash
# Set up billing alerts
aws budgets create-budget \
  --account-id YOUR-ACCOUNT-ID \
  --budget '{
    "BudgetName": "Matomo-Monthly-Budget",
    "BudgetLimit": {"Amount": "50", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }'
```

#### Resource Tagging for Cost Tracking
```python
# In CDK stacks, add consistent tags
cdk.Tags.of(self).add("Project", "Matomo")
cdk.Tags.of(self).add("Environment", "Production")
cdk.Tags.of(self).add("CostCenter", "Analytics")
```

## 📈 Scaling Cost Considerations

### Traffic-Based Scaling

| Monthly Visits | Recommended Configuration | Estimated Cost |
|----------------|--------------------------|----------------|
| **< 10,000** | t3.micro + db.t3.micro | $45 |
| **10k - 100k** | t3.micro + db.t3.micro | $55 |
| **100k - 500k** | t3.small + db.t3.small | $85 |
| **500k - 1M** | t3.medium + db.t3.medium | $140 |
| **> 1M** | t3.large + db.t3.large + ALB | $250+ |

### Auto Scaling Considerations
```python
# For high traffic, implement auto scaling
auto_scaling_group = autoscaling.AutoScalingGroup(
    self, "MatomoASG",
    vpc=vpc,
    instance_type=ec2.InstanceType("t3.micro"),
    machine_image=amzn_linux,
    min_capacity=1,
    max_capacity=3,
    desired_capacity=1
)

# Scale based on CPU utilization
auto_scaling_group.scale_on_cpu_utilization(
    "CpuScaling",
    target_utilization_percent=70
)
```

## 🔍 Cost Monitoring Tools

### AWS Cost Explorer Queries
```bash
# Monthly cost by service
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-02-01 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Daily costs for specific resources
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity DAILY \
  --metrics BlendedCost \
  --filter '{"Tags":{"Key":"Project","Values":["Matomo"]}}'
```

### CloudWatch Cost Metrics
```python
# Create custom metrics for tracking
cloudwatch.Metric(
    namespace="AWS/Billing",
    metric_name="EstimatedCharges",
    dimensions_map={
        "Currency": "USD",
        "ServiceName": "AmazonEC2"
    }
)
```

## 💡 Advanced Cost Optimization

### 1. Serverless Migration (Future)
Consider migrating to serverless for very low traffic:
- **AWS Lambda** for API processing
- **Amazon Aurora Serverless** for database
- **CloudFront** for content delivery

**Potential Savings**: 80-90% for low-traffic sites

### 2. Multi-Region Cost Considerations

| Region | EC2 t3.micro/hour | Data Transfer | Notes |
|--------|-------------------|---------------|-------|
| **us-east-1** | $0.0104 | $0.09/GB | Cheapest |
| **us-west-2** | $0.0104 | $0.09/GB | Same as us-east-1 |
| **eu-west-1** | $0.0114 | $0.09/GB | ~10% more expensive |
| **ap-southeast-1** | $0.0116 | $0.12/GB | Most expensive |

### 3. Data Lifecycle Management
```bash
# Implement data archiving in Matomo
echo "0 2 * * * /usr/bin/php /var/www/html/console core:archive" | sudo crontab -

# Archive old logs to S3 (cheaper storage)
aws s3 sync /var/www/html/tmp/logs/ s3://matomo-archive-bucket/logs/
```

## 🎯 Recommended Configurations

### Startup/Personal ($45-50/month)
```json
{
  "enableDatabase": true,
  "instanceType": "t3.micro",
  "costOptimized": true,
  "databaseConfig": {
    "instanceClass": "db.t3.micro",
    "backupRetention": 0
  }
}
```

### Small Business ($50-60/month)
```json
{
  "enableDatabase": true,
  "instanceType": "t3.micro",
  "databaseConfig": {
    "instanceClass": "db.t3.micro",
    "backupRetention": 1
  }
}
```

### Enterprise ($100-150/month)
```json
{
  "enableDatabase": true,
  "instanceType": "t3.small",
  "costOptimized": false,
  "databaseConfig": {
    "instanceClass": "db.t3.small",
    "multiAZ": true,
    "backupRetention": 7
  }
}
```

## 📋 Cost Optimization Checklist

### Monthly Review
- [ ] Check AWS Cost Explorer for unexpected charges
- [ ] Review CloudWatch metrics for unused resources
- [ ] Verify free tier usage remaining
- [ ] Clean up old snapshots and backups
- [ ] Review data transfer patterns

### Quarterly Review
- [ ] Evaluate Reserved Instance opportunities
- [ ] Consider upgrading/downgrading instance types
- [ ] Review storage growth and optimization
- [ ] Assess need for multi-AZ deployment
- [ ] Plan for traffic growth

### Annual Review
- [ ] Compare costs with alternatives (hosted solutions)
- [ ] Evaluate serverless migration opportunities
- [ ] Review security vs cost trade-offs
- [ ] Plan for scaling requirements

---

**Remember**: The cheapest solution isn't always the best. Balance cost optimization with performance, security, and reliability requirements for your specific use case.