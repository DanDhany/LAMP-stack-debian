#!/bin/bash
set -e

if [ "$#" -ne 2 ]; then
    echo "Penggunaan: $0 <nama_proyek> <versi_php>"
    exit 1
fi

PROJECT_NAME=$1
PHP_VERSION=$2
WEB_ROOT="/var/www/html"
APACHE_CONFIG_FILE="/etc/apache2/conf-available/php-per-project.conf"
PROJECT_PATH="${WEB_ROOT}/${PROJECT_NAME}"
SOCKET_PATH="/run/php/php${PHP_VERSION}-fpm.sock"

if [ ! -d "${PROJECT_PATH}" ]; then
    echo "Error: Folder proyek tidak ditemukan di ${PROJECT_PATH}"
    exit 1
fi

if [ ! -e "${SOCKET_PATH}" ]; then
    echo "Error: Socket PHP-FPM untuk versi ${PHP_VERSION} tidak ditemukan."
    exit 1
fi

CONFIG_BLOCK="
<Directory \"${PROJECT_PATH}\">
    Require all granted
    <FilesMatch \.php$>
        SetHandler \"proxy:unix:${SOCKET_PATH}|fcgi://localhost/\"
    </FilesMatch>
</Directory>
"

sed -i "/<Directory \"${PROJECT_PATH//\//\\/}\">/,/<\/Directory>/d" "${APACHE_CONFIG_FILE}"
echo "${CONFIG_BLOCK}" >> "${APACHE_CONFIG_FILE}"

echo "Konfigurasi untuk proyek '${PROJECT_NAME}' telah diatur ke PHP ${PHP_VERSION}."

apache2ctl configtest
if [ $? -eq 0 ]; then
    if [ -d /run/systemd/system ]; then
        systemctl reload apache2
    else
        service apache2 reload
    fi
    echo "Apache berhasil di-reload."
else
    echo "ERROR: Konfigurasi Apache baru mengandung error. Apache tidak di-reload."
    exit 1
fi
exit 0