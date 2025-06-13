#!/bin/bash

# Variables (will be replaced by CDK)
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-matomo}"
DB_USER="${DB_USER:-matomo}"
DB_PASSWORD="${DB_PASSWORD}"
REGION="${AWS_REGION:-us-east-1}"
SECRET_ARN="${SECRET_ARN}"

# Simple log function using echo and tee
logit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/matomo-install.log
}

logit "Starting Matomo installation"

# Update system
logit "Updating system packages"
dnf update -y

# Install required packages
logit "Installing Apache, PHP, and required extensions"
dnf install -y \
    httpd \
    php \
    php-mysqlnd \
    php-gd \
    php-xml \
    php-mbstring \
    php-json \
    php-curl \
    php-zip \
    php-opcache \
    mariadb105 \
    awscli \
    unzip \
    wget

# Start and enable Apache
logit "Starting Apache service"
systemctl start httpd
systemctl enable httpd

# Configure PHP
logit "Configuring PHP settings"
echo "memory_limit = 256M" >> /etc/php.ini
echo "upload_max_filesize = 64M" >> /etc/php.ini
echo "post_max_size = 64M" >> /etc/php.ini
echo "max_execution_time = 300" >> /etc/php.ini
echo "date.timezone = UTC" >> /etc/php.ini

# Download and install Matomo
logit "Downloading Matomo"
cd /tmp
wget -O matomo-latest.zip https://builds.matomo.org/matomo-latest.zip
logit "Extracting Matomo"
unzip -q matomo-latest.zip

# Move Matomo to web directory
logit "Installing Matomo files"
rm -rf /var/www/html/*
mv matomo/* /var/www/html/
rm -rf /tmp/matomo*

# Set correct permissions
logit "Setting file permissions"
chown -R apache:apache /var/www/html/
chmod -R 755 /var/www/html/

# Create directories if they don't exist and set permissions
if [ -d "/var/www/html/tmp" ]; then
    chmod -R 777 /var/www/html/tmp/
fi
if [ -d "/var/www/html/config" ]; then
    chmod -R 777 /var/www/html/config/
fi

# Get database credentials from Secrets Manager if available
if [ ! -z "$SECRET_ARN" ]; then
    logit "Retrieving database credentials from Secrets Manager"
    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$REGION" --query SecretString --output text 2>/dev/null || echo "")
    if [ ! -z "$SECRET_JSON" ]; then
        DB_PASSWORD=$(echo "$SECRET_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])" 2>/dev/null || echo "")
        DB_USER=$(echo "$SECRET_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['username'])" 2>/dev/null || echo "matomo")
        logit "Database credentials retrieved successfully"
    else
        logit "Could not retrieve database credentials"
    fi
fi

# Configure Apache virtual host
logit "Configuring Apache virtual host with PHP-FPM security settings"
cat > /etc/httpd/conf.d/matomo.conf << 'APACHEEOF'
<VirtualHost *:80>
    DocumentRoot /var/www/html
    ErrorLog /var/log/httpd/matomo_error.log
    CustomLog /var/log/httpd/matomo_access.log combined
    
    # Security fix for PHP-FPM: Prevent direct access to sensitive directories
    ProxyPass /config !
    ProxyPass /tmp !
    ProxyPass /lang !
    ProxyPass /libs !
    
    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>
    
    # Additional security: Block access to sensitive files and directories
    <Location "/config">
        Require all denied
    </Location>
    
    <Location "/tmp">
        Require all denied
    </Location>
    
    <Files "*.log">
        Require all denied
    </Files>
    
    <Files "config.ini.php">
        Require all denied
    </Files>
</VirtualHost>
APACHEEOF

# Setup log rotation for Matomo
logit "Setting up log rotation"
cat > /etc/logrotate.d/matomo << 'LOGROTATEEOF'
/var/log/httpd/matomo_*.log {
    daily
    missingok
    rotate 52
    compress
    notifempty
    create 644 apache apache
}
LOGROTATEEOF

# Create a status file to indicate installation completion
logit "Creating installation status file"
cat > /var/www/html/INSTALLATION_STATUS << 'STATUSEOF'
Matomo installation completed at: $(date)
Database Host: $DB_HOST
Database Name: $DB_NAME
Log file: /var/log/matomo-install.log

Next steps:
1. Access Matomo via your EC2 instance's public IP address
2. Complete the web-based installation if database was not auto-configured
3. Follow the setup wizard to create your first website

Security reminder:
- Change default passwords
- Configure trusted hosts in config.ini.php
- Review security settings in the Matomo admin panel
STATUSEOF

logit "Matomo installation completed successfully"
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "IP-NOT-FOUND")
logit "Access Matomo at: http://$PUBLIC_IP/"
logit "Installation script finished at: $(date)"

# Restart Apache to ensure everything is loaded
logit "Restarting Apache to finalize installation"
systemctl restart httpd

logit "Final status check"
systemctl status httpd --no-pager