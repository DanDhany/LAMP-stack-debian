#!/bin/bash
set -e

# --- Variabel Global untuk Logging ---
# Pastikan LOG_FILE ditentukan dengan cara yang sama seperti install.sh
# Namun, karena set_php_version.sh bisa dipanggil kapan saja,
# kita akan menggunakan file log yang lebih umum atau membuatnya jika belum ada.
# Untuk tujuan ini, kita akan asumsikan ada folder /var/log/dashboard/
# Atau lebih baik, kita bisa log ke syslog jika mau, tapi untuk konsistensi,
# kita akan gunakan pendekatan file log yang bisa di-tail.

# Kita akan buat log file spesifik untuk set_php_version,
# atau bisa juga append ke log file utama install.sh jika path-nya diketahui.
# Untuk saat ini, kita akan buat log terpisah agar lebih mudah.
LOG_DIR="/var/log/dashboard"
LOG_FILE="${LOG_DIR}/set_php_version_$(date +%Y%m%d).log" # Log per hari

# Pastikan direktori log ada
mkdir -p "$LOG_DIR" || { echo "Gagal membuat direktori log: $LOG_DIR. Keluar."; exit 1; }

# --- FUNGSI BANTUAN (Dengan Logging) ---
log_message_local() {
    local type="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$type] [set_php_version.sh] $message" | tee -a "$LOG_FILE"
}

print_info_local() { log_message_local "INFO" "\e[34m🔵 INFO: $1\e[0m"; }
print_success_local() { log_message_local "SUCCESS" "\e[32m✅ SUKSES: $1\e[0m"; }
print_error_local() { log_message_local "ERROR" "\e[31m❌ ERROR: $1\e[0m"; }

# Pastikan script dijalankan dengan sudo oleh www-data
if [ "$(id -u)" != "0" ]; then
    print_error_local "Skrip ini harus dijalankan sebagai root atau dengan sudo. (Current user: $(whoami))"
    exit 1
fi

if [ "$#" -ne 2 ]; then
    print_error_local "Penggunaan: $0 <nama_proyek> <versi_php>"
    exit 1
fi

PROJECT_NAME=$1
PHP_VERSION=$2
WEB_ROOT="/var/www/html"
APACHE_CONFIG_FILE="/etc/apache2/conf-available/php-per-project.conf"
PROJECT_PATH="${WEB_ROOT}/${PROJECT_NAME}"
SOCKET_PATH="/run/php/php${PHP_VERSION}-fpm.sock"

print_info_local "Mencoba mengatur proyek '${PROJECT_NAME}' ke PHP ${PHP_VERSION}..."

if [ ! -d "${PROJECT_PATH}" ]; then
    print_error_local "Folder proyek tidak ditemukan di ${PROJECT_PATH}. Pastikan nama proyek benar."
    exit 1
fi

if [ ! -e "${SOCKET_PATH}" ]; then
    print_error_local "Socket PHP-FPM untuk versi ${PHP_VERSION} tidak ditemukan. Pastikan versi PHP terinstal dan berjalan."
    exit 1
fi

# Escape karakter khusus dalam PROJECT_PATH untuk sed
ESCAPED_PROJECT_PATH=$(echo "$PROJECT_PATH" | sed 's/[\/&]/\\&/g')

# Hapus konfigurasi lama untuk proyek ini dari file
print_info_local "Menghapus konfigurasi lama untuk proyek '${PROJECT_NAME}' dari ${APACHE_CONFIG_FILE}..."
sed -i "/<Directory \"${ESCAPED_PROJECT_PATH}\">/,/<\/Directory>/d" "${APACHE_CONFIG_FILE}"

# Tambahkan konfigurasi baru
print_info_local "Menambahkan konfigurasi baru untuk proyek '${PROJECT_NAME}' (PHP ${PHP_VERSION})..."
CONFIG_BLOCK="
# Konfigurasi untuk Proyek: ${PROJECT_NAME}
<Directory \"${PROJECT_PATH}\">
    Require all granted
    <FilesMatch \.php$>
        SetHandler \"proxy:unix:${SOCKET_PATH}|fcgi://localhost/\"
    </FilesMatch>
</Directory>
"
echo "${CONFIG_BLOCK}" | tee -a "${APACHE_CONFIG_FILE}"

# Reload Apache
print_info_local "Mereload konfigurasi Apache..."
if [ -d /run/systemd/system ]; then
    systemctl reload apache2 || { print_error_local "Gagal mereload Apache. Periksa konfigurasi Apache dan log sistem."; exit 1; }
else
    service apache2 reload || { print_error_local "Gagal mereload Apache. Periksa konfigurasi Apache dan log sistem."; exit 1; }
fi

print_success_local "Proyek '${PROJECT_NAME}' berhasil diatur ke PHP ${PHP_VERSION} dan Apache berhasil di-reload."
exit 0