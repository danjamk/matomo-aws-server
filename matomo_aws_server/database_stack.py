from aws_cdk import (
    Stack,
    aws_rds as rds,
    aws_ec2 as ec2,
    aws_secretsmanager as secretsmanager,
    RemovalPolicy,
    CfnOutput,
    Duration,
)
from constructs import Construct


class DatabaseStack(Stack):
    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        vpc: ec2.Vpc,
        database_security_group: ec2.SecurityGroup,
        private_subnets: list,
        config: dict,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, description="Matomo Analytics - RDS MySQL database with Secrets Manager integration", **kwargs)
        
        self.vpc = vpc
        self.database_security_group = database_security_group
        self.private_subnets = private_subnets
        self.config = config
        db_config = config.get("databaseConfig", {})
        
        # Create database credentials secret
        self.db_secret = secretsmanager.Secret(
            self, "DatabaseCredentials",
            description="Matomo database credentials",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "matomo"}',
                generate_string_key="password",
                exclude_characters=" @'\"\\%+~`#$&*()|[]{}:;<>?!/",
                password_length=32,
            )
        )
        
        # Create DB subnet group
        db_subnet_group = rds.SubnetGroup(
            self, "DatabaseSubnetGroup",
            description="Subnet group for Matomo database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=self.private_subnets)
        )
        
        # Create RDS instance
        self.database = rds.DatabaseInstance(
            self, "MatomoDatabase",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO
            ),
            allocated_storage=db_config.get("allocatedStorage", 20),
            storage_type=rds.StorageType.GP2,
            credentials=rds.Credentials.from_secret(self.db_secret),
            database_name="matomo",
            vpc=self.vpc,
            subnet_group=db_subnet_group,
            security_groups=[self.database_security_group],
            multi_az=db_config.get("multiAZ", False),
            backup_retention=Duration.days(db_config.get("backupRetention", 0)) if db_config.get("backupRetention", 0) > 0 else None,
            deletion_protection=False,
            removal_policy=RemovalPolicy.DESTROY,
            auto_minor_version_upgrade=True,
            enable_performance_insights=False,  # Avoid additional charges
        )
        
        # Create outputs
        self._create_outputs()
    
    def _create_outputs(self):
        CfnOutput(
            self, "DatabaseEndpoint",
            value=self.database.instance_endpoint.hostname,
            description="RDS database endpoint"
        )
        
        CfnOutput(
            self, "DatabasePort",
            value=str(self.database.instance_endpoint.port),
            description="RDS database port"
        )
        
        CfnOutput(
            self, "DatabaseName",
            value="matomo",
            description="Database name"
        )
        
        CfnOutput(
            self, "DatabaseSecretArn",
            value=self.db_secret.secret_arn,
            description="ARN of the secret containing database credentials"
        )
        
        CfnOutput(
            self, "DatabaseConnectionString",
            value=f"mysql://matomo:{{password}}@{self.database.instance_endpoint.hostname}:{self.database.instance_endpoint.port}/matomo",
            description="Database connection string template (password from secrets manager)"
        )