# Testing the PHP-Apache Configuration Fix

## Overview

This document provides instructions on how to test the PHP-Apache configuration fix in a virtual environment.

## Prerequisites

1. VirtualBox or VMware installed
2. Vagrant installed (for Vagrant testing)
3. Docker installed (for Docker testing)

## Testing with Vagrant

### 1. Start the Vagrant Environment

```bash
vagrant up
```

This will:
- Create a Debian 12 VM
- Install the LAMP stack using the updated install.sh script
- Configure Apache with proper PHP handling

### 2. Access the Dashboard

After provisioning is complete, access:
- Dashboard: http://localhost:8088/
- phpMyAdmin: http://localhost:8088/phpmyadmin
- File Manager: http://localhost:8088/file-manager/

### 3. Verify PHP Execution

Check that PHP files are properly executed rather than displayed as source code:
- Visit http://localhost:8088/test_project_phpinfo/ - should show PHP info page
- Visit http://localhost:8088/test_project_hello/ - should show "Hello World" message
- Visit http://localhost:8088/phpmyadmin - should show phpMyAdmin login page

## Testing with Docker

### 1. Build and Run Docker Container

```bash
docker-compose up -d
```

### 2. Enter the Container

```bash
docker exec -it dashboard-test-container /bin/bash
```

### 3. Run the Installation Script

```bash
cd /home/tester
sudo ./install.sh
```

Follow the prompts to complete installation.

### 4. Test PHP Execution

Create a test file:
```bash
echo '<?php echo "PHP is working correctly!"; ?>' | sudo tee /var/www/html/test.php
```

Visit http://localhost:8080/test.php - should display "PHP is working correctly!" rather than the PHP code.

## Manual Testing Steps

### 1. Check Apache Modules

```bash
apache2ctl -M | grep -E "(proxy|fcgi|rewrite)"
```

Should show:
- proxy_module
- proxy_http_module
- proxy_fcgi_module
- rewrite_module

### 2. Check PHP-FPM Status

```bash
systemctl status php{version}-fpm
```

Should show the service as active and running.

### 3. Check Configuration Files

Verify the following files exist and have correct content:
- `/etc/apache2/conf-available/php-dashboard.conf`
- `/etc/apache2/sites-available/000-default.conf`

### 4. Test PHP File Execution

Create a test file:
```bash
echo '<?php phpinfo(); ?>' | sudo tee /var/www/html/info.php
```

Visit http://your-server/info.php - should display the PHP information page.

## Troubleshooting

### If PHP Code is Still Displayed as Text

1. Check Apache error logs:
   ```bash
   tail -f /var/log/apache2/error.log
   ```

2. Verify the SetHandler directive in Apache configuration:
   ```bash
   grep -r "SetHandler.*proxy:unix" /etc/apache2/
   ```

3. Check PHP-FPM socket permissions:
   ```bash
   ls -la /run/php/php*-fpm.sock
   ```

4. Test PHP-FPM directly:
   ```bash
   sudo -u www-data php-fpm{version} -t
   ```

### Common Issues and Solutions

1. **Missing Apache Modules**:
   ```bash
   sudo a2enmod proxy proxy_http proxy_fcgi setenvif rewrite
   sudo systemctl restart apache2
   ```

2. **PHP-FPM Not Running**:
   ```bash
   sudo systemctl start php{version}-fpm
   sudo systemctl enable php{version}-fpm
   ```

3. **Incorrect Socket Path**:
   Verify the socket path in Apache configuration matches the actual socket file location.

4. **Permission Issues**:
   Ensure Apache can read the socket file and web directories.

## Validation Checklist

- [ ] Apache modules are properly enabled
- [ ] PHP-FPM is running and accessible
- [ ] Apache configuration includes proper SetHandler directives
- [ ] PHP files execute correctly rather than display as source
- [ ] phpMyAdmin loads properly
- [ ] Test projects work with different PHP versions
- [ ] No errors in Apache error log related to PHP handling

## Conclusion

After following these testing procedures, you should have verified that:
1. PHP files are properly executed by Apache
2. phpMyAdmin works correctly
3. The multi-PHP version management system functions as expected
4. All components are properly integrated and configured