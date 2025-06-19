import json
import boto3
import logging
from datetime import datetime
import os
import urllib.request
import urllib.error
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Collect Matomo-specific metrics and send to CloudWatch
    """
    try:
        # Get configuration from environment variables
        matomo_url = os.environ.get('MATOMO_URL')
        if not matomo_url:
            logger.error("MATOMO_URL environment variable not set")
            return {'statusCode': 400, 'body': 'MATOMO_URL not configured'}
        
        # Collect various Matomo metrics
        metrics_data = []
        
        # 1. Check if Matomo is responding (availability metric)
        try:
            start_time = time.time()
            req = urllib.request.Request(matomo_url)
            response = urllib.request.urlopen(req, timeout=30)
            end_time = time.time()
            
            availability = 1 if response.status == 200 else 0
            response_time_ms = (end_time - start_time) * 1000
            
            metrics_data.append({
                'MetricName': 'Availability',
                'Value': availability,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
            
            # Response time metric
            metrics_data.append({
                'MetricName': 'ResponseTime',
                'Value': response_time_ms,
                'Unit': 'Milliseconds',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
            
            logger.info(f"Matomo availability check: {availability}, Response time: {response_time_ms}ms")
            
        except (urllib.error.URLError, urllib.error.HTTPError, Exception) as e:
            logger.error(f"Failed to reach Matomo: {e}")
            metrics_data.append({
                'MetricName': 'Availability',
                'Value': 0,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
        
        # 2. Check if installation is complete by looking for config file
        try:
            config_check_url = f"{matomo_url}/config/config.ini.php"
            req = urllib.request.Request(config_check_url)
            config_response = urllib.request.urlopen(req, timeout=10)
            # If we get a 403 (forbidden), config exists but is protected (good)
            # If we get 200, config exists
            installation_complete = 1 if config_response.status in [403, 200] else 0
            
            metrics_data.append({
                'MetricName': 'InstallationComplete',
                'Value': installation_complete,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
            
            logger.info(f"Matomo installation status: {installation_complete}")
            
        except urllib.error.HTTPError as e:
            # 403 means config exists but is protected (good)
            installation_complete = 1 if e.code == 403 else 0
            metrics_data.append({
                'MetricName': 'InstallationComplete',
                'Value': installation_complete,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
            logger.info(f"Matomo installation status (HTTP {e.code}): {installation_complete}")
        except Exception as e:
            logger.warning(f"Could not check installation status: {e}")
            metrics_data.append({
                'MetricName': 'InstallationComplete',
                'Value': 0,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
        
        # 3. Database connectivity check (indirect via Matomo API)
        try:
            # Try to access a simple Matomo API endpoint that requires DB
            api_url = f"{matomo_url}/index.php?module=API&method=SitesManager.getSitesWithViewAccess&format=json&token_auth=anonymous"
            req = urllib.request.Request(api_url)
            api_response = urllib.request.urlopen(req, timeout=15)
            
            # Even if we get an auth error, it means Matomo and DB are working
            database_connectivity = 1 if api_response.status in [200, 401, 403] else 0
            
            metrics_data.append({
                'MetricName': 'DatabaseConnectivity',
                'Value': database_connectivity,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
            
            logger.info(f"Database connectivity check: {database_connectivity}")
            
        except urllib.error.HTTPError as e:
            # Even auth errors mean the app and DB are working
            database_connectivity = 1 if e.code in [401, 403] else 0
            metrics_data.append({
                'MetricName': 'DatabaseConnectivity',
                'Value': database_connectivity,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
            logger.info(f"Database connectivity check (HTTP {e.code}): {database_connectivity}")
        except Exception as e:
            logger.warning(f"Database connectivity check failed: {e}")
            metrics_data.append({
                'MetricName': 'DatabaseConnectivity',
                'Value': 0,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Application', 'Value': 'Matomo'}
                ]
            })
        
        # Send metrics to CloudWatch
        if metrics_data:
            try:
                cloudwatch.put_metric_data(
                    Namespace='Matomo/Application',
                    MetricData=metrics_data
                )
                logger.info(f"Successfully sent {len(metrics_data)} metrics to CloudWatch")
            except Exception as e:
                logger.error(f"Failed to send metrics to CloudWatch: {e}")
                return {'statusCode': 500, 'body': f'Failed to send metrics: {str(e)}'}
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully collected {len(metrics_data)} Matomo metrics',
                'metrics': [m['MetricName'] for m in metrics_data]
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error in lambda_handler: {e}")
        return {'statusCode': 500, 'body': f'Unexpected error: {str(e)}'}