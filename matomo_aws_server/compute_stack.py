from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_ssm as ssm,
    CfnOutput,
)
from constructs import Construct


class ComputeStack(Stack):
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: ec2.Vpc,
        public_subnets: list,
        web_security_group: ec2.SecurityGroup,
        database_stack=None,
        config: dict = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, description="Matomo Analytics - EC2 instance with automated Matomo installation and SSH key management", **kwargs)
        
        self.vpc = vpc
        self.public_subnets = public_subnets
        self.web_security_group = web_security_group
        self.database_stack = database_stack
        self.config = config or {}
        
        # Create EC2 key pair
        self.key_pair = self._create_key_pair()
        
        # Create IAM role for EC2
        self.ec2_role = self._create_ec2_role()
        
        # Create EC2 instance
        self.instance = self._create_ec2_instance()
        
        # Create outputs
        self._create_outputs()
    
    def _create_key_pair(self):
        """Create EC2 Key Pair and store in Parameter Store"""
        key_pair_name = f"{self.config.get('projectName', 'matomo')}-keypair"
        
        # Use the higher-level KeyPair construct
        key_pair = ec2.KeyPair(
            self, "MatomoKeyPair", 
            key_pair_name=key_pair_name,
            type=ec2.KeyPairType.RSA,
            format=ec2.KeyPairFormat.PEM,
        )
        
        # The KeyPair construct automatically stores the private key in Parameter Store
        # We don't need to create a separate StringParameter - it's already done
        # The parameter name will be: /ec2/keypair/{key_pair_name}
        
        return key_pair
    
    def _create_ec2_role(self):
        """Create IAM role for EC2 instance"""
        role = iam.Role(
            self, "MatomoEC2Role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="Role for Matomo EC2 instance",
        )
        
        # Add permissions to read from Parameter Store
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath",
            ],
            resources=[
                f"arn:aws:ssm:{self.region}:{self.account}:parameter/ec2/keypair/*"
            ]
        ))
        
        # Add permissions to read from Secrets Manager if database is enabled
        if self.database_stack:
            role.add_to_policy(iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "secretsmanager:GetSecretValue",
                ],
                resources=[
                    self.database_stack.db_secret.secret_arn
                ]
            ))
        
        return role
    
    def _create_ec2_instance(self):
        """Create EC2 instance with Matomo installation"""
        # Read user data script
        import os
        script_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "user-data", "install-matomo.sh")
        with open(script_path, "r") as f:
            user_data_script = f.read()
        
        # Replace variables in user data script
        if self.database_stack:
            user_data_script = user_data_script.replace(
                "${DB_HOST}", self.database_stack.database.instance_endpoint.hostname
            )
            user_data_script = user_data_script.replace(
                "${DB_NAME}", "matomo"
            )
            user_data_script = user_data_script.replace(
                "${SECRET_ARN}", self.database_stack.db_secret.secret_arn
            )
        else:
            user_data_script = user_data_script.replace("${DB_HOST}", "localhost")
            user_data_script = user_data_script.replace("${SECRET_ARN}", "")
        
        user_data_script = user_data_script.replace("${AWS_REGION}", self.region)
        
        # Create user data
        user_data = ec2.UserData.for_linux()
        # Add the entire script as a single bash script
        user_data.add_commands(f"cat > /tmp/install-matomo.sh << 'EOF'\n{user_data_script}\nEOF")
        user_data.add_commands("chmod +x /tmp/install-matomo.sh")
        user_data.add_commands("/tmp/install-matomo.sh")
        
        # Get latest Amazon Linux 2023 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2023()
        
        # Create instance
        instance = ec2.Instance(
            self, "MatomoInstance",
            instance_type=ec2.InstanceType(self.config.get("instanceType", "t3.micro")),
            machine_image=amzn_linux,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=self.public_subnets),
            security_group=self.web_security_group,
            key_pair=self.key_pair,
            role=self.ec2_role,
            user_data=user_data,
            user_data_causes_replacement=True,
        )
        
        # Add tags
        from aws_cdk import Tags
        Tags.of(instance).add("Name", f"{self.config.get('projectName', 'matomo')}-server")
        
        return instance
    
    def _create_outputs(self):
        """Create CloudFormation outputs"""
        CfnOutput(
            self, "InstanceId",
            value=self.instance.instance_id,
            description="EC2 Instance ID"
        )
        
        CfnOutput(
            self, "PublicIp",
            value=self.instance.instance_public_ip,
            description="Public IP address of the Matomo server"
        )
        
        CfnOutput(
            self, "PublicDns",
            value=self.instance.instance_public_dns_name,
            description="Public DNS name of the Matomo server"
        )
        
        CfnOutput(
            self, "MatomoUrl",
            value=f"http://{self.instance.instance_public_ip}",
            description="Matomo web interface URL"
        )
        
        CfnOutput(
            self, "SshKeyParameterName",
            value=f"/ec2/keypair/{self.key_pair.key_pair_id}",
            description="Parameter Store name for SSH private key"
        )
        
        CfnOutput(
            self, "SshCommand",
            value=f"aws ssm get-parameter --name '/ec2/keypair/{self.key_pair.key_pair_id}' --with-decryption --query 'Parameter.Value' --output text > matomo-key.pem && chmod 400 matomo-key.pem && ssh -i matomo-key.pem ec2-user@{self.instance.instance_public_ip}",
            description="SSH command to connect to the instance (retrieve key from Parameter Store first)"
        )