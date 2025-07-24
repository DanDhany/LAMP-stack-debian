#!/bin/bash

# Test script to verify PHP-Apache configuration fix

echo "Testing PHP-Apache Configuration Fix"
echo "===================================="

# Check if running on Debian/Ubuntu system
if ! command -v lsb_release &> /dev/null; then
    echo "This test script is designed for Debian/Ubuntu systems."
    echo "Exiting..."
    exit 1
fi

# Check if Apache is installed
if ! command -v apache2 &> /dev/null; then
    echo "Apache is not installed. Please install Apache first."
    exit 1
fi

# Check if PHP is installed
if ! command -v php &> /dev/null; then
    echo "PHP is not installed. Please install PHP first."
    exit 1
fi

# Check Apache modules
echo "Checking required Apache modules..."
REQUIRED_MODULES=("proxy" "proxy_http" "proxy_fcgi" "setenvif" "rewrite")
MISSING_MODULES=()

for module in "${REQUIRED_MODULES[@]}"; do
    if apache2ctl -M 2>/dev/null | grep -q "${module}_module"; then
        echo "  ✓ ${module} module is enabled"
    else
        echo "  ✗ ${module} module is NOT enabled"
        MISSING_MODULES+=("$module")
    fi
done

if [ ${#MISSING_MODULES[@]} -gt 0 ]; then
    echo "Missing modules: ${MISSING_MODULES[*]}"
    echo "Please enable them with: a2enmod ${MISSING_MODULES[*]}"
    exit 1
fi

# Check PHP-FPM status
echo "Checking PHP-FPM status..."
PHP_VERSIONS=$(ls /etc/php/ 2>/dev/null | grep -E '^[0-9]+\.[0-9]+$' || true)

if [ -z "$PHP_VERSIONS" ]; then
    echo "No PHP versions found in /etc/php/"
    exit 1
fi

for version in $PHP_VERSIONS; do
    if systemctl is-active --quiet "php${version}-fpm"; then
        echo "  ✓ PHP-FPM ${version} is running"
        
        # Check if socket exists
        SOCKET_PATH="/run/php/php${version}-fpm.sock"
        if [ -e "$SOCKET_PATH" ]; then
            echo "  ✓ PHP-FPM socket exists: $SOCKET_PATH"
        else
            echo "  ✗ PHP-FPM socket not found: $SOCKET_PATH"
        fi
    else
        echo "  ✗ PHP-FPM ${version} is NOT running"
    fi
done

# Check Apache configuration syntax
echo "Checking Apache configuration syntax..."
if apache2ctl configtest; then
    echo "  ✓ Apache configuration is valid"
else
    echo "  ✗ Apache configuration has errors"
    exit 1
fi

# Create test PHP file
echo "Creating test PHP file..."
WEB_ROOT="/var/www/html"
TEST_FILE="${WEB_ROOT}/test_php_config.php"

if [ -w "$WEB_ROOT" ]; then
    cat > "$TEST_FILE" <<EOF
<?php
// PHP Configuration Test
echo "<h1>PHP Configuration Test</h1>";
echo "<p>PHP Version: " . phpversion() . "</p>";
echo "<p>Server Software: " . \$_SERVER['SERVER_SOFTWARE'] . "</p>";
echo "<p>Server API: " . php_sapi_name() . "</p>";

// Show PHP info
echo "<h2>PHP Configuration Details</h2>";
phpinfo(INFO_GENERAL | INFO_CONFIGURATION | INFO_MODULES);
?>
EOF
    
    chown www-data:www-data "$TEST_FILE" 2>/dev/null || true
    echo "  ✓ Created test file: $TEST_FILE"
    echo "  You can test it by visiting: http://localhost/test_php_config.php"
else
    echo "  ✗ Cannot write to web root: $WEB_ROOT"
fi

# Check Apache virtual host configuration
echo "Checking Apache virtual host configuration..."
DEFAULT_SITE="/etc/apache2/sites-available/000-default.conf"

if [ -r "$DEFAULT_SITE" ]; then
    echo "  Default site configuration:"
    grep -E "^[^#]" "$DEFAULT_SITE" | sed 's/^/    /'
else
    echo "  ✗ Default site configuration not found: $DEFAULT_SITE"
fi

echo "Test completed."