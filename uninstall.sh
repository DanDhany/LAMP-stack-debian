#!/bin/bash
set -e
print_info() { echo -e "\n\e[34m🔵 INFO: $1\e[0m"; }
print_success() { echo -e "\e[32m✅ SUKSES: $1\e[0m"; }
print_error() { echo -e "\e[31m❌ ERROR: $1\e[0m"; }
confirm_uninstall() {
    clear; echo "======================================================================"
    echo "          Skrip Uninstall untuk Dashboard Server Otomatis"
    echo "======================================================================"; echo ""
    echo -e "\e[31mPERINGATAN:\e[0m Skrip ini akan MENGHAPUS komponen berikut:"
    echo "  - Apache2, MariaDB, phpMyAdmin"
    echo "  - Semua versi PHP dari repositori Sury.org"
    echo "  - Semua file di /var/www/html"
    echo "  - Semua database MariaDB (termasuk data di dalamnya)"
    echo "  - Semua file konfigurasi terkait."; echo ""
    read -p "Anda yakin ingin melanjutkan? Data tidak akan bisa dikembalikan. [y/N] " -n 1 -r; echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then echo "Proses uninstall dibatalkan."; exit 1; fi
}
stop_and_disable_services() {
    print_info "Menghentikan dan menonaktifkan semua service terkait..."
    if [ -d /run/systemd/system ]; then
        systemctl stop apache2 mariadb || true; systemctl disable apache2 mariadb || true
    else
        service apache2 stop || true; service mariadb stop || true
    fi
}
purge_packages() {
    print_info "Menghapus paket-paket utama (purge)..."
    apt-get purge --auto-remove -y apache2* mariadb-* phpmyadmin
    print_info "Menghapus semua paket PHP..."; apt-get purge --auto-remove -y "php*" || true
}
remove_manual_files() {
    print_info "Menghapus file repositori dan GPG Key..."; rm -f /etc/apt/sources.list.d/php.list; rm -f /usr/share/keyrings/deb.sury.org-php.gpg
    print_info "Menghapus file dan direktori kustom lainnya..."
    rm -f /usr/local/bin/set_php_version.sh; rm -f /etc/sudoers.d/www-data-php-manager
    rm -f /etc/apache2/conf-available/php-per-project.conf
    print_info "Menghapus semua konten web di /var/www/html..."; rm -rf /var/www/html/*
    print_info "Menghapus semua data database MariaDB..."; rm -rf /var/lib/mysql
}
final_cleanup() {
    print_info "Membersihkan sisa paket yang tidak dibutuhkan..."; apt-get autoremove -y; apt-get update
}
main() {
    if [ "$(id -u)" != "0" ]; then print_error "Skrip ini harus dijalankan sebagai root atau dengan sudo."; exit 1; fi
    confirm_uninstall; stop_and_disable_services; purge_packages; remove_manual_files; final_cleanup
    print_success "Proses uninstall selesai. Server Anda telah dibersihkan."
}
main