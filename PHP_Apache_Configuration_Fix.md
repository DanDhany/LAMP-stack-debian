# PHP-Apache Configuration Fix for LAMP Stack

## Problem Analysis

The issue where PHP code is displayed as plain text instead of being executed by Apache is a common problem in LAMP (Linux, Apache, MySQL, PHP) stack configurations. This typically occurs when Apache is not properly configured to handle PHP files.

## Root Causes

1. **Missing PHP Handler**: Apache doesn't have the proper handler configured to process PHP files
2. **Incorrect Module Configuration**: Required Apache modules for PHP processing are not enabled
3. **PHP-FPM Socket Issues**: Problems with PHP-FPM (FastCGI Process Manager) socket connections
4. **Configuration File Structure**: Incorrect Apache configuration file organization or loading order

## Solution Implementation

### 1. Apache Module Configuration

The following Apache modules must be enabled for proper PHP processing:
- `proxy`: Required for proxy functionality
- `proxy_http`: Required for HTTP proxy support
- `proxy_fcgi`: Required for FastCGI proxy support
- `setenvif`: Required for environment variable setting
- `rewrite`: Required for URL rewriting

```bash
a2enmod proxy proxy_http proxy_fcgi setenvif rewrite
```

### 2. PHP-FPM Configuration

Instead of using mod_php, the system uses PHP-FPM for better performance and isolation. Each PHP version has its own FPM service that creates a Unix socket:

```
/run/php/php{version}-fpm.sock
```

### 3. Apache Virtual Host Configuration

The key fix is in properly configuring the Apache virtual host to handle PHP files through the FastCGI proxy:

```apache
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    
    # PHP Configuration for main web root
    <Directory "/var/www/html">
        Require all granted
        <FilesMatch \.php$>
            SetHandler "proxy:unix:/run/php/php{version}-fpm.sock|fcgi://localhost/var/www/html"
        </FilesMatch>
    </Directory>
    
    # PHP Configuration for phpMyAdmin
    Alias /phpmyadmin /usr/share/phpmyadmin
    <Directory /usr/share/phpmyadmin>
        Require all granted
        <FilesMatch \.php$>
            SetHandler "proxy:unix:/run/php/php{version}-fpm.sock|fcgi://localhost/usr/share/phpmyadmin"
        </FilesMatch>
    </Directory>
</VirtualHost>
```

### 4. Key Configuration Points

1. **SetHandler Directive**: This is the critical directive that tells Apache how to handle PHP files
2. **Socket Path**: Must match the actual PHP-FPM socket path for the specific PHP version
3. **Document Root in FCGI URL**: Including the document root in the fcgi:// URL ensures proper path resolution
4. **FilesMatch Block**: Ensures only .php files are processed by PHP-FPM

## phpMyAdmin Specific Configuration

phpMyAdmin requires special attention because:
1. It's typically installed in `/usr/share/phpmyadmin`
2. It needs to be accessible via `/phpmyadmin` alias
3. It must use the same PHP version as the main application for consistency

## Per-Project PHP Version Management

The system allows different projects to use different PHP versions through dynamic configuration:

1. Each project can be assigned a specific PHP version
2. The `set_php_version.sh` script modifies the Apache configuration
3. Project-specific configuration blocks are added to the main config file
4. Apache is reloaded to apply changes

## Testing the Fix

After implementing the configuration changes:

1. **Restart Services**:
   ```bash
   systemctl restart apache2
   systemctl restart php{version}-fpm
   ```

2. **Create Test File**:
   ```php
   <?php phpinfo(); ?>
   ```
   Save as `/var/www/html/test.php`

3. **Access via Browser**:
   Visit `http://your-server/test.php`
   
   If properly configured, you should see the PHP information page rather than the PHP code.

## Common Troubleshooting Steps

1. **Check Apache Error Logs**:
   ```bash
   tail -f /var/log/apache2/error.log
   ```

2. **Verify PHP-FPM Status**:
   ```bash
   systemctl status php{version}-fpm
   ```

3. **Check Socket Permissions**:
   ```bash
   ls -la /run/php/php{version}-fpm.sock
   ```

4. **Test PHP-FPM Directly**:
   ```bash
   php-fpm{version} -t
   ```

## Security Considerations

1. **File Permissions**: Ensure proper ownership and permissions for web files
2. **Directory Restrictions**: Use `Require all granted` carefully and only where needed
3. **PHP Configuration**: Review php.ini settings for security
4. **Apache Hardening**: Implement security headers and modules

## Conclusion

The fix involves properly configuring Apache to use PHP-FPM through FastCGI proxy handlers. The key is ensuring the `SetHandler` directive is correctly configured with the proper socket path and document root in the FCGI URL. This approach provides better performance and security compared to traditional mod_php while ensuring PHP files are properly executed instead of displayed as plain text.