from aws_cdk import (
    Stack,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_logs as logs,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_events as events,
    aws_events_targets as targets,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct
import os


class MonitoringStack(Stack):
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        compute_stack,
        database_stack=None,
        networking_stack=None,
        config: dict = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, description="Matomo Analytics - CloudWatch monitoring, dashboards, and alarms", **kwargs)
        
        self.compute_stack = compute_stack
        self.database_stack = database_stack
        self.networking_stack = networking_stack
        self.config = config or {}
        self.monitoring_config = config.get("monitoring", {})
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create Lambda function for Matomo metrics collection
        self.metrics_lambda = self._create_metrics_lambda()
        
        # Create CloudWatch dashboard
        if self.monitoring_config.get("enableDashboard", True):
            self.dashboard = self._create_dashboard()
        
        # Create CloudWatch alarms
        if self.monitoring_config.get("enableAlarms", True):
            self._create_alarms()
        
        # Create outputs
        self._create_outputs()
    
    def _create_notification_topic(self):
        """Create SNS topic for alarm notifications"""
        topic = sns.Topic(
            self, "MonitoringAlerts",
            display_name="Matomo Monitoring Alerts",
            topic_name=f"{self.config.get('projectName', 'matomo')}-monitoring-alerts"
        )
        
        # Add email subscription if provided
        notification_email = self.monitoring_config.get("notificationEmail")
        if notification_email:
            topic.add_subscription(
                sns_subscriptions.EmailSubscription(notification_email)
            )
        
        return topic
    
    def _create_metrics_lambda(self):
        """Create Lambda function for collecting Matomo-specific metrics"""
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self, "MatomoMetricsLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add CloudWatch permissions
        lambda_role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "cloudwatch:PutMetricData"
            ],
            resources=["*"]
        ))
        
        # Get the Lambda code path
        lambda_code_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "lambda")
        
        # Create log group for Lambda with explicit lifecycle management
        lambda_log_group = logs.LogGroup(
            self, "MatomoMetricsCollectorLogGroup",
            log_group_name=f"/aws/lambda/matomo-metrics-collector",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create Lambda function
        metrics_lambda = _lambda.Function(
            self, "MatomoMetricsCollector",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="matomo_metrics_collector.lambda_handler",
            code=_lambda.Code.from_asset(lambda_code_path),
            role=lambda_role,
            timeout=Duration.minutes(2),
            log_group=lambda_log_group,
            environment={
                "MATOMO_URL": f"http://{self.compute_stack.instance.instance_public_ip}"
            },
            description="Collects Matomo application metrics and sends to CloudWatch"
        )
        
        # Create EventBridge rule to trigger Lambda every 5 minutes
        schedule_rule = events.Rule(
            self, "MatomoMetricsSchedule",
            schedule=events.Schedule.rate(Duration.minutes(5)),
            description="Trigger Matomo metrics collection every 5 minutes"
        )
        
        # Add Lambda as target
        schedule_rule.add_target(targets.LambdaFunction(metrics_lambda))
        
        return metrics_lambda
    
    def _create_dashboard(self):
        """Create CloudWatch dashboard with key metrics"""
        dashboard = cloudwatch.Dashboard(
            self, "MatomoDashboard",
            dashboard_name=f"{self.config.get('projectName', 'matomo')}-monitoring",
            period_override=cloudwatch.PeriodOverride.AUTO,
        )
        
        # EC2 Instance Metrics
        ec2_cpu_widget = cloudwatch.GraphWidget(
            title="EC2 CPU Utilization",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="CPUUtilization",
                    dimensions_map={"InstanceId": self.compute_stack.instance.instance_id},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        ec2_network_widget = cloudwatch.GraphWidget(
            title="EC2 Network I/O",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkIn",
                    dimensions_map={"InstanceId": self.compute_stack.instance.instance_id},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkOut",
                    dimensions_map={"InstanceId": self.compute_stack.instance.instance_id},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        ec2_status_widget = cloudwatch.SingleValueWidget(
            title="EC2 Status Checks",
            metrics=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="StatusCheckFailed",
                    dimensions_map={"InstanceId": self.compute_stack.instance.instance_id},
                    statistic="Maximum",
                    period=Duration.minutes(1)
                )
            ],
            width=6,
            height=6
        )
        
        # Add EC2 widgets to dashboard
        dashboard.add_widgets(ec2_cpu_widget)
        dashboard.add_widgets(ec2_network_widget, ec2_status_widget)
        
        # Matomo Application Metrics
        matomo_availability_widget = cloudwatch.GraphWidget(
            title="Matomo Application Availability",
            left=[
                cloudwatch.Metric(
                    namespace="Matomo/Application",
                    metric_name="Availability",
                    dimensions_map={"Application": "Matomo"},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            width=6,
            height=6
        )
        
        matomo_response_time_widget = cloudwatch.GraphWidget(
            title="Matomo Response Time",
            left=[
                cloudwatch.Metric(
                    namespace="Matomo/Application",
                    metric_name="ResponseTime",
                    dimensions_map={"Application": "Matomo"},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            width=6,
            height=6
        )
        
        matomo_status_widget = cloudwatch.SingleValueWidget(
            title="Matomo System Status",
            metrics=[
                cloudwatch.Metric(
                    namespace="Matomo/Application",
                    metric_name="InstallationComplete",
                    dimensions_map={"Application": "Matomo"},
                    statistic="Maximum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="Matomo/Application", 
                    metric_name="DatabaseConnectivity",
                    dimensions_map={"Application": "Matomo"},
                    statistic="Maximum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # Add Matomo widgets to dashboard
        dashboard.add_widgets(matomo_availability_widget, matomo_response_time_widget)
        dashboard.add_widgets(matomo_status_widget)
        
        # Database Metrics (if database is enabled)
        if self.database_stack:
            db_cpu_widget = cloudwatch.GraphWidget(
                title="RDS CPU Utilization",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/RDS",
                        metric_name="CPUUtilization",
                        dimensions_map={"DBInstanceIdentifier": self.database_stack.database.instance_identifier},
                        statistic="Average",
                        period=Duration.minutes(5)
                    )
                ],
                width=12,
                height=6
            )
            
            db_connections_widget = cloudwatch.GraphWidget(
                title="RDS Database Connections",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/RDS",
                        metric_name="DatabaseConnections",
                        dimensions_map={"DBInstanceIdentifier": self.database_stack.database.instance_identifier},
                        statistic="Average",
                        period=Duration.minutes(5)
                    )
                ],
                width=6,
                height=6
            )
            
            db_storage_widget = cloudwatch.SingleValueWidget(
                title="RDS Free Storage (GB)",
                metrics=[
                    cloudwatch.Metric(
                        namespace="AWS/RDS",
                        metric_name="FreeStorageSpace",
                        dimensions_map={"DBInstanceIdentifier": self.database_stack.database.instance_identifier},
                        statistic="Average",
                        period=Duration.minutes(5)
                    ).with_(
                        unit=cloudwatch.Unit.BYTES
                    )
                ],
                width=6,
                height=6
            )
            
            # Add database widgets to dashboard
            dashboard.add_widgets(db_cpu_widget)
            dashboard.add_widgets(db_connections_widget, db_storage_widget)
        
        return dashboard
    
    def _create_alarms(self):
        """Create CloudWatch alarms for critical metrics"""
        # EC2 Instance Alarms
        
        # High CPU Alarm
        ec2_high_cpu_alarm = cloudwatch.Alarm(
            self, "EC2HighCPUAlarm",
            alarm_name=f"{self.config.get('projectName', 'matomo')}-ec2-high-cpu",
            alarm_description="EC2 instance CPU utilization is too high",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                dimensions_map={"InstanceId": self.compute_stack.instance.instance_id},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        ec2_high_cpu_alarm.add_alarm_action(cw_actions.SnsAction(self.notification_topic))
        
        # Instance Status Check Alarm
        ec2_status_alarm = cloudwatch.Alarm(
            self, "EC2StatusCheckAlarm",
            alarm_name=f"{self.config.get('projectName', 'matomo')}-ec2-status-check",
            alarm_description="EC2 instance status check failed",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="StatusCheckFailed",
                dimensions_map={"InstanceId": self.compute_stack.instance.instance_id},
                statistic="Maximum",
                period=Duration.minutes(1)
            ),
            threshold=0,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        ec2_status_alarm.add_alarm_action(cw_actions.SnsAction(self.notification_topic))
        
        # Database Alarms (if database is enabled)
        if self.database_stack:
            # High Database CPU Alarm
            db_high_cpu_alarm = cloudwatch.Alarm(
                self, "DBHighCPUAlarm",
                alarm_name=f"{self.config.get('projectName', 'matomo')}-db-high-cpu",
                alarm_description="RDS database CPU utilization is too high",
                metric=cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="CPUUtilization",
                    dimensions_map={"DBInstanceIdentifier": self.database_stack.database.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                threshold=80,
                evaluation_periods=3,
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
            )
            db_high_cpu_alarm.add_alarm_action(cw_actions.SnsAction(self.notification_topic))
            
            # Database Connection Count Alarm
            db_connections_alarm = cloudwatch.Alarm(
                self, "DBHighConnectionsAlarm",
                alarm_name=f"{self.config.get('projectName', 'matomo')}-db-high-connections",
                alarm_description="RDS database connection count is too high",
                metric=cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="DatabaseConnections",
                    dimensions_map={"DBInstanceIdentifier": self.database_stack.database.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                threshold=50,  # Adjust based on instance type
                evaluation_periods=2,
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
            )
            db_connections_alarm.add_alarm_action(cw_actions.SnsAction(self.notification_topic))
            
            # Low Storage Space Alarm
            db_low_storage_alarm = cloudwatch.Alarm(
                self, "DBLowStorageAlarm",
                alarm_name=f"{self.config.get('projectName', 'matomo')}-db-low-storage",
                alarm_description="RDS database free storage space is too low",
                metric=cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="FreeStorageSpace",
                    dimensions_map={"DBInstanceIdentifier": self.database_stack.database.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                threshold=2000000000,  # 2GB in bytes
                evaluation_periods=2,
                comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
            )
            db_low_storage_alarm.add_alarm_action(cw_actions.SnsAction(self.notification_topic))
        
        # Matomo Application Alarms
        
        # Matomo Availability Alarm
        matomo_down_alarm = cloudwatch.Alarm(
            self, "MatomoDownAlarm",
            alarm_name=f"{self.config.get('projectName', 'matomo')}-application-down",
            alarm_description="Matomo application is not responding",
            metric=cloudwatch.Metric(
                namespace="Matomo/Application",
                metric_name="Availability",
                dimensions_map={"Application": "Matomo"},
                statistic="Maximum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )
        matomo_down_alarm.add_alarm_action(cw_actions.SnsAction(self.notification_topic))
        
        # Matomo High Response Time Alarm
        matomo_slow_alarm = cloudwatch.Alarm(
            self, "MatomoSlowResponseAlarm",
            alarm_name=f"{self.config.get('projectName', 'matomo')}-slow-response",
            alarm_description="Matomo application response time is too high",
            metric=cloudwatch.Metric(
                namespace="Matomo/Application",
                metric_name="ResponseTime",
                dimensions_map={"Application": "Matomo"},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5000,  # 5 seconds in milliseconds
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        matomo_slow_alarm.add_alarm_action(cw_actions.SnsAction(self.notification_topic))
        
        # Matomo Database Connectivity Alarm
        matomo_db_alarm = cloudwatch.Alarm(
            self, "MatomoDatabaseConnectivityAlarm",
            alarm_name=f"{self.config.get('projectName', 'matomo')}-database-connectivity",
            alarm_description="Matomo cannot connect to database",
            metric=cloudwatch.Metric(
                namespace="Matomo/Application",
                metric_name="DatabaseConnectivity",
                dimensions_map={"Application": "Matomo"},
                statistic="Maximum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )
        matomo_db_alarm.add_alarm_action(cw_actions.SnsAction(self.notification_topic))
    
    def _create_outputs(self):
        """Create CloudFormation outputs"""
        CfnOutput(
            self, "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for monitoring notifications"
        )
        
        if hasattr(self, 'dashboard'):
            CfnOutput(
                self, "DashboardUrl",
                value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
                description="CloudWatch dashboard URL"
            )
        
        CfnOutput(
            self, "MonitoringStackStatus",
            value="Enabled",
            description="Monitoring stack deployment status"
        )
        
        CfnOutput(
            self, "MetricsLambdaFunction",
            value=self.metrics_lambda.function_name,
            description="Lambda function name for Matomo metrics collection"
        )