from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    CfnOutput,
)
from constructs import Construct


class NetworkingStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, config: dict, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.config = config
        networking_config = config.get("networking", {})
        
        # Create VPC
        # Note: RDS requires at least 2 AZs for subnet groups, so min is 2 even for cost optimization
        self.vpc = ec2.Vpc(
            self, "MatomoVPC",
            ip_addresses=ec2.IpAddresses.cidr(networking_config.get("vpcCidr", "10.0.0.0/16")),
            max_azs=2,  # Always use 2 AZs minimum for RDS compatibility
            nat_gateways=1 if networking_config.get("singleNatGateway", True) else None,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
        )
        
        # Get subnet references
        self.public_subnets = self.vpc.public_subnets
        self.private_subnets = self.vpc.private_subnets
        
        # Create Security Groups
        self._create_security_groups()
        
        # Create outputs
        self._create_outputs()
    
    def _create_security_groups(self):
        # Web Security Group (for EC2 instance)
        self.web_security_group = ec2.SecurityGroup(
            self, "WebSecurityGroup",
            vpc=self.vpc,
            description="Security group for Matomo web server",
            allow_all_outbound=True,
        )
        
        # Allow SSH access
        allowed_ssh_cidr = self.config.get("allowedSshCidr", "0.0.0.0/0")
        self.web_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(allowed_ssh_cidr),
            connection=ec2.Port.tcp(22),
            description="SSH access"
        )
        
        # Allow HTTP access
        self.web_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP access"
        )
        
        # Allow HTTPS access
        self.web_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS access"
        )
        
        # Database Security Group (for RDS)
        self.database_security_group = ec2.SecurityGroup(
            self, "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for Matomo database",
            allow_all_outbound=False,
        )
        
        # Allow MySQL access from web security group only
        self.database_security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.web_security_group.security_group_id),
            connection=ec2.Port.tcp(3306),
            description="MySQL access from web servers"
        )
    
    def _create_outputs(self):
        CfnOutput(
            self, "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for Matomo deployment"
        )
        
        CfnOutput(
            self, "PublicSubnetIds",
            value=",".join([subnet.subnet_id for subnet in self.public_subnets]),
            description="Public subnet IDs"
        )
        
        CfnOutput(
            self, "PrivateSubnetIds", 
            value=",".join([subnet.subnet_id for subnet in self.private_subnets]),
            description="Private subnet IDs"
        )
        
        CfnOutput(
            self, "WebSecurityGroupId",
            value=self.web_security_group.security_group_id,
            description="Security group ID for web servers"
        )
        
        CfnOutput(
            self, "DatabaseSecurityGroupId",
            value=self.database_security_group.security_group_id,
            description="Security group ID for database"
        )