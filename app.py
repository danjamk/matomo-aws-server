#!/usr/bin/env python3
import os
import aws_cdk as cdk
from matomo_aws_server.networking_stack import NetworkingStack
from matomo_aws_server.database_stack import DatabaseStack
from matomo_aws_server.compute_stack import ComputeStack
from matomo_aws_server.monitoring_stack import MonitoringStack

app = cdk.App()

# Get configuration from CDK context
config = app.node.try_get_context("matomo") or {}
project_name = config.get("projectName", "matomo-analytics")
enable_database = config.get("enableDatabase", False)
enable_monitoring = config.get("enableMonitoring", False)

# Create environment configuration
env = cdk.Environment(
    account=os.getenv('CDK_DEFAULT_ACCOUNT'),
    region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
)

# Deploy networking stack first
networking_stack = NetworkingStack(
    app, 
    f"{project_name}-networking",
    config=config,
    env=env
)

# Optionally deploy database stack
database_stack = None
if enable_database:
    database_stack = DatabaseStack(
        app,
        f"{project_name}-database", 
        vpc=networking_stack.vpc,
        database_security_group=networking_stack.database_security_group,
        private_subnets=networking_stack.private_subnets,
        config=config,
        env=env
    )

# Deploy compute stack
compute_stack = ComputeStack(
    app,
    f"{project_name}-compute",
    vpc=networking_stack.vpc,
    public_subnets=networking_stack.public_subnets,
    web_security_group=networking_stack.web_security_group,
    database_stack=database_stack,
    config=config,
    env=env
)

# Optionally deploy monitoring stack
monitoring_stack = None
if enable_monitoring:
    monitoring_stack = MonitoringStack(
        app,
        f"{project_name}-monitoring",
        compute_stack=compute_stack,
        database_stack=database_stack,
        networking_stack=networking_stack,
        config=config,
        env=env
    )
    # Add dependencies to all other stacks
    monitoring_stack.add_dependency(compute_stack)
    if database_stack:
        monitoring_stack.add_dependency(database_stack)

# Add stack dependencies
if database_stack:
    compute_stack.add_dependency(database_stack)
compute_stack.add_dependency(networking_stack)

app.synth()