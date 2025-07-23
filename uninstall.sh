#!/bin/bash
set -e
print_info() { echo -e "\n\e[34m🔵 INFO: $1\e[0m"; }
print_success() { echo -e "\e[32m✅ SUKSES: $1\e[0m"; }
print_error() { echo -e "\e[31m❌ ERROR: $1\e[0m"; }
confirm_uninstall() {
    clear; echo "======================================================================"
    echo "          Skrip Uninstall untuk Dashboard Server Otomatis"
    echo "======================================================================"; echo ""
    echo -e "\e[31mPERINGATAN:\e[0m Skrip ini akan MENGHAPUS semua komponen..."; echo "" # Diringkas
    read -p "Anda yakin ingin melanjutkan? [y/N] " -n 1 -r; echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then echo "Proses uninstall dibatalkan."; exit 1; fi
}
stop_and_disable_services() {
    print_info "Menghentikan service..."
    if [ -d /run/systemd/system ]; then
        systemctl stop apache2 mariadb || true; systemctl disable apache2 mariadb || true
    else
        service apache2 stop || true; service mariadb stop || true
    fi
}
purge_packages() {
    print_info "Menghapus paket-paket..."; apt-get purge --auto-remove -y apache2* mariadb-* phpmyadmin "php*" || true
}
remove_manual_files() {
    print_info "Menghapus file manual..."
    rm -f /etc/apt/sources.list.d/php.list; rm -f /usr/share/keyrings/deb.sury.org-php.gpg
    rm -f /usr/local/bin/set_php_version.sh; rm -f /etc/sudoers.d/www-data-php-manager
    rm -f /etc/apache2/conf-available/php-per-project.conf
    rm -rf /var/www/html/*; rm -rf /var/lib/mysql
    # DIPERBARUI: Hapus juga file lock
    rm -f /tmp/.dashboard_install_lock
}
final_cleanup() {
    print_info "Membersihkan sisa paket..."; apt-get autoremove -y; apt-get update
}
main() {
    if [ "$(id -u)" != "0" ]; then print_error "Skrip harus dijalankan sebagai root."; exit 1; fi
    confirm_uninstall; stop_and_disable_services; purge_packages; remove_manual_files; final_cleanup
    print_success "Proses uninstall selesai."
}
main