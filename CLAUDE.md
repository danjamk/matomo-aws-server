This project deploys an AWS EC2 server with Matomo web analytics server.
It will use CDK written in Python to deploy the server and all infrastructure needed to run Matomo.
A MySQL database server will be an optional component based on user needs

I created a similar project for a client, and I am now open-sourcing it for anyone to use.
you can find the existing project here: /Users/danjamk/GitHub/matomo-ec2-server
You can use this project as a reference, but there are likely better ways for doing most of it
I also want to structure this project in a way that is easy to use and understand for anyone who 
wants to deploy Matomo on AWS EC2.

This github repo will be referenced by a medium.com article.  I have place the article in this project 
for your reference.  I will remove it at the end.
Owning your Marketing Analytics and Deploying Matomo at AWS with CDK.md

# Architecture & Implementation Context

## Project Goals
- Cost-optimized deployment (single AZ, minimal resources)
- Easy deploy/test/destroy workflow for development
- Secure credential management using AWS services
- Multi-stack CDK architecture for maintainability

## Architecture Decision
Based on analysis of the reference implementation, this project uses a 3-stack approach:
1. NetworkingStack - VPC, subnets, security groups (single AZ for cost optimization)
2. DatabaseStack - Optional RDS MySQL (db.t3.micro, 20GB, single AZ)
3. ComputeStack - EC2 instance (t3.micro) with Matomo installation

## Security & Secrets Management
- EC2 Key Pairs stored in AWS Systems Manager Parameter Store (SecureString)
- Database passwords stored in AWS Secrets Manager
- Matomo admin credentials stored in AWS Secrets Manager
- All secrets accessible only by deployed resources with minimal IAM permissions

## Configuration Approach
- CDK context in cdk.json for deployment-time configuration
- Environment variables for sensitive/dynamic configuration
- Cost-optimized defaults with options for production-grade settings

## Key Improvements Over Reference Implementation
- Proper parameterization and configuration management
- Secure credential handling (no local files)
- Multi-stack architecture for better lifecycle management
- Comprehensive outputs for easy access to connection details
- Cost optimization while maintaining security best practices

## Expected Costs (Monthly)
- EC2 t3.micro: $0 (free tier) or ~$7.50
- RDS db.t3.micro: $0 (free tier) or ~$12.50  
- NAT Gateway: ~$32
- Storage: ~$1-2
- Total: ~$32-55/month depending on free tier eligibility (RDS MySQL required for Matomo)


