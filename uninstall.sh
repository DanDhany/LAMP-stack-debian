#!/bin/bash

# ==============================================================================
#   Skrip Uninstall Total untuk Dashboard Server & Multi-PHP Manager
# ==============================================================================

# Keluar segera jika ada perintah yang gagal
set -e

# -- VARIABEL --
PHP_VERSIONS_TO_PURGE=("7.4" "8.2")

# -- FUNGSI --
print_info() { echo -e "\n\e[34m🔵 INFO: $1\e[0m"; }
print_success() { echo -e "\e[32m✅ SUKSES: $1\e[0m"; }
print_error() { echo -e "\e[31m❌ ERROR: $1\e[0m"; }

confirm_uninstall() {
    clear
    echo "======================================================================"
    echo "          Skrip Uninstall untuk Dashboard Server Otomatis"
    echo "======================================================================"
    echo ""
    echo -e "\e[31mPERINGATAN:\e[0m Skrip ini akan MENGHAPUS komponen berikut:"
    echo "  - Apache2, MariaDB, phpMyAdmin, Shell In A Box"
    echo "  - Semua versi PHP dari PPA Ondřej Surý"
    echo "  - Semua file di /var/www/html (termasuk dashboard & file manager)"
    echo "  - Semua database MariaDB (termasuk data di dalamnya)"
    echo "  - Semua file konfigurasi terkait."
    echo ""
    read -p "Anda yakin ingin melanjutkan? Data tidak akan bisa dikembalikan. [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Proses uninstall dibatalkan."
        exit 1
    fi
}

stop_and_disable_services() {
    print_info "Menghentikan dan menonaktifkan semua service terkait..."
    systemctl stop apache2 mariadb shellinabox || true
    systemctl disable apache2 mariadb shellinabox || true
}

purge_packages() {
    print_info "Menghapus paket-paket utama (purge)..."
    apt-get purge --auto-remove -y apache2* mariadb-* phpmyadmin shellinabox
    
    print_info "Menghapus semua paket PHP dari PPA..."
    for version in "${PHP_VERSIONS_TO_PURGE[@]}"; do
        apt-get purge --auto-remove -y "php${version}*"
    done
}

remove_ppa() {
    print_info "Menghapus PPA Ondřej Surý..."
    if command -v add-apt-repository &> /dev/null; then
        add-apt-repository --remove ppa:ondrej/php -y
    else
        rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list
    fi
}

remove_manual_files() {
    print_info "Menghapus file dan direktori yang dibuat secara manual..."
    rm -f /usr/local/bin/set_php_version.sh
    rm -f /etc/sudoers.d/www-data-php-manager
    rm -f /etc/apache2/conf-available/php-per-project.conf
    rm -f /etc/apache2/conf-available/shellinabox.conf
    
    print_info "Menghapus semua konten web di /var/www/html..."
    rm -rf /var/www/html/*
    
    print_info "Menghapus semua data database MariaDB..."
    rm -rf /var/lib/mysql
}

final_cleanup() {
    print_info "Membersihkan sisa paket yang tidak dibutuhkan..."
    apt-get autoremove -y
    apt-get update
}

# -- EKSEKUSI SKRIP --
main() {
    if [ "$(id -u)" != "0" ]; then
       print_error "Skrip ini harus dijalankan sebagai root atau dengan sudo."
       exit 1
    fi
    
    confirm_uninstall
    stop_and_disable_services
    purge_packages
    remove_ppa
    remove_manual_files
    final_cleanup
    
    print_success "Proses uninstall selesai. Server Anda telah dibersihkan."
}

main