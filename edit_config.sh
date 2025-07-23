#!/bin/bash

# ==============================================================================
#   Skrip Editor Konfigurasi untuk Dashboard Server
# ==============================================================================

set -e

# -- FUNGSI BANTUAN --
print_info() { echo -e "\n\e[34m🔵 INFO: $1\e[0m"; }
print_success() { echo -e "\e[32m✅ SUKSES: $1\e[0m"; }
print_error() { echo -e "\e[31m❌ ERROR: $1\e[0m"; }

check_root() {
    if [ "$(id -u)" != "0" ]; then
       print_error "Skrip ini harus dijalankan sebagai root atau dengan sudo."
       exit 1
    fi
}

# -- FUNGSI-FUNGSI UTAMA --

change_mariadb_root_pass() {
    print_info "Mengubah Password Root MariaDB"
    read -sp "Masukkan password root MariaDB SAAT INI (jika lupa, cek instalasi awal): " OLD_PASS
    echo ""
    read -sp "Masukkan password root MariaDB BARU: " NEW_PASS
    echo ""
    read -sp "Konfirmasi password BARU: " NEW_PASS_CONFIRM
    echo ""

    if [ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]; then
        print_error "Password baru tidak cocok. Proses dibatalkan."
        return 1
    fi

    if mysqladmin -u root -p"$OLD_PASS" password "$NEW_PASS"; then
        print_success "Password root MariaDB berhasil diubah."
    else
        print_error "Gagal mengubah password. Pastikan password saat ini benar."
    fi
}

change_pma_user_pass() {
    print_info "Mengubah Password User phpMyAdmin"
    read -sp "Untuk melanjutkan, masukkan password root MariaDB: " MARIADB_ROOT_PASS
    echo ""
    read -p "Masukkan nama user phpMyAdmin yang akan diubah: " PMA_USER
    read -sp "Masukkan password BARU untuk user '$PMA_USER': " PMA_PASS
    echo ""

    if mysql -u root -p"$MARIADB_ROOT_PASS" -e "ALTER USER '$PMA_USER'@'localhost' IDENTIFIED BY '$PMA_PASS'; FLUSH PRIVILEGES;"; then
        print_success "Password untuk user '$PMA_USER' berhasil diubah."
    else
        print_error "Gagal mengubah password. Pastikan password root dan nama user benar."
    fi
}

change_tfm_credentials() {
    print_info "Mengubah Kredensial Tiny File Manager"
    local tfm_file="/var/www/html/file-manager/index.php"
    if [ ! -f "$tfm_file" ]; then
        print_error "File Tiny File Manager tidak ditemukan di $tfm_file."
        return 1
    fi
    
    read -p "Masukkan username BARU untuk File Manager: " TFM_USER
    read -sp "Masukkan password BARU untuk File Manager: " TFM_PASS
    echo ""

    local TFM_PASS_HASH=$(php -r "echo password_hash('$TFM_PASS', PASSWORD_DEFAULT);")
    
    # Hapus semua user lama di dalam array
    sed -i "/^\s*'\w*'\s*=>/d" "$tfm_file"
    # Sisipkan user baru
    sed -i "/\$auth_users = array(/a \ \ \ \ '$TFM_USER' => '$TFM_PASS_HASH'," "$tfm_file"
    
    print_success "Kredensial File Manager berhasil diubah menjadi: $TFM_USER"
}

change_siab_port() {
    print_info "Mengubah Port Web SSH (Shell In A Box)"
    local siab_conf="/etc/default/shellinabox"
    local apache_conf="/etc/apache2/conf-available/shellinabox.conf"

    read -p "Masukkan port BARU untuk Web SSH: " SIAB_PORT

    if ! [[ "$SIAB_PORT" =~ ^[0-9]+$ ]]; then
        print_error "Port harus berupa angka. Proses dibatalkan."
        return 1
    fi

    sed -i "s/^SHELLINABOX_PORT=.*/SHELLINABOX_PORT=${SIAB_PORT}/" "$siab_conf"
    sed -i "s#ProxyPass http://127.0.0.1:.*#ProxyPass http://127.0.0.1:${SIAB_PORT}/#" "$apache_conf"
    sed -i "s#ProxyPassReverse http://127.0.0.1:.*#ProxyPassReverse http://127.0.0.1:${SIAB_PORT}/#" "$apache_conf"

    print_info "Me-restart service terkait..."
    systemctl restart shellinabox
    systemctl reload apache2
    
    print_success "Port Web SSH berhasil diubah ke $SIAB_PORT. URL baru: http://<ip_server>/ssh/"
}

# -- TAMPILAN MENU --
main_menu() {
    while true; do
        echo ""
        echo "======================================="
        echo "      Editor Konfigurasi Dashboard"
        echo "======================================="
        echo "1. Ubah Password Root MariaDB"
        echo "2. Ubah Password User phpMyAdmin"
        echo "3. Ubah Kredensial File Manager"
        echo "4. Ubah Port Web SSH"
        echo "5. Keluar"
        echo "======================================="
        read -p "Pilih opsi [1-5]: " choice

        case $choice in
            1) change_mariadb_root_pass ;;
            2) change_pma_user_pass ;;
            3) change_tfm_credentials ;;
            4) change_siab_port ;;
            5) break ;;
            *) print_error "Pilihan tidak valid." ;;
        esac
    done
}

# -- EKSEKUSI SKRIP --
check_root
main_menu
print_info "Selesai."