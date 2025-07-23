#!/bin/bash

# ==============================================================================
#   Skrip Editor Konfigurasi untuk Dashboard Server (Versi Lanjutan)
# ==============================================================================

set -e

# -- FUNGSI BANTUAN & VARIABEL --
print_info() { echo -e "\n\e[34m🔵 INFO: $1\e[0m"; }
print_success() { echo -e "\e[32m✅ SUKSES: $1\e[0m"; }
print_error() { echo -e "\e[31m❌ ERROR: $1\e[0m"; }
PHP_VERSIONS_STABLE=("8.3" "8.2" "8.1" "8.0" "7.4" "5.6")

check_root() {
    if [ "$(id -u)" != "0" ]; then print_error "Skrip ini harus dijalankan sebagai root atau dengan sudo."; exit 1; fi
}
restart_php_fpm() {
    local version=$1
    echo "Me-restart PHP-FPM untuk versi $version..."
    if [ -d /run/systemd/system ]; then systemctl restart "php${version}-fpm"; else service "php${version}-fpm" restart; fi
}

# -- FUNGSI-FUNGSI UTAMA --

install_php_version() {
    print_info "Instalasi Versi PHP Baru"
    # Dapatkan versi terinstal
    local installed_versions=($(ls /etc/php/ | grep -E '^[0-9]+\.[0-9]+$' || true))
    # Dapatkan versi yang tersedia TAPI belum terinstal
    local available_to_install=()
    for v_stable in "${PHP_VERSIONS_STABLE[@]}"; do
        is_installed=false
        for v_installed in "${installed_versions[@]}"; do
            if [ "$v_stable" = "$v_installed" ]; then is_installed=true; break; fi
        done
        if [ "$is_installed" = false ]; then available_to_install+=("$v_stable"); fi
    done

    if [ ${#available_to_install[@]} -eq 0 ]; then print_warning "Semua versi PHP stabil sudah terinstal."; return; fi

    PS3="Pilih versi PHP baru untuk diinstal: "; select version in "${available_to_install[@]}"; do
        if [ -n "$version" ]; then
            print_info "Menginstal PHP ${version}..."
            local extensions=("mysql" "xml" "curl" "zip" "mbstring" "bcmath" "soap" "intl" "gd")
            if (( $(echo "$version < 8.0" | bc -l) )); then extensions+=("json"); fi
            local packages_to_install=("php${version}" "php${version}-fpm")
            for ext in "${extensions[@]}"; do packages_to_install+=("php${version}-${ext}"); done
            apt-get install -y "${packages_to_install[@]}"
            print_success "PHP ${version} berhasil diinstal."
            break
        else echo "Pilihan tidak valid."; fi
    done
}

uninstall_php_version() {
    print_info "Uninstalasi Versi PHP"
    local installed_versions=($(ls /etc/php/ | grep -E '^[0-9]+\.[0-9]+$' || true))
    if [ ${#installed_versions[@]} -eq 0 ]; then print_warning "Tidak ada versi PHP yang terinstal."; return; fi
    
    PS3="Pilih versi PHP yang akan dihapus: "; select version in "${installed_versions[@]}"; do
        if [ -n "$version" ]; then
            read -p "Anda yakin ingin menghapus PHP ${version} dan semua ekstensinya? [y/N] " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                print_info "Menghapus PHP ${version}..."
                apt-get purge --auto-remove -y "php${version}*"
                print_success "PHP ${version} berhasil dihapus."
            else echo "Proses dibatalkan."; fi
            break
        else echo "Pilihan tidak valid."; fi
    done
}

manage_extensions() {
    print_info "Manajemen Ekstensi PHP"
    local installed_versions=($(ls /etc/php/ | grep -E '^[0-9]+\.[0-9]+$' || true))
    if [ ${#installed_versions[@]} -eq 0 ]; then print_warning "Tidak ada versi PHP yang terinstal."; return; fi
    
    PS3="Pilih versi PHP yang akan dikelola: "; select version in "${installed_versions[@]}"; do
        if [ -n "$version" ]; then
            while true; do
                echo ""
                print_info "Mengelola Ekstensi untuk PHP $version"
                echo "Status Ekstensi (CLI):"
                php$version -m | column
                echo "------------------------------------"
                echo "1. Aktifkan Ekstensi"
                echo "2. Nonaktifkan Ekstensi"
                echo "3. Kembali ke Menu Utama"
                read -p "Pilih opsi [1-3]: " ext_choice
                
                case $ext_choice in
                    1) read -p "Masukkan nama ekstensi untuk diaktifkan (misal: xdebug): " ext_name
                       if phpenmod -v "$version" "$ext_name" 2>/dev/null; then
                           restart_php_fpm "$version"
                           print_success "Ekstensi '$ext_name' berhasil diaktifkan untuk PHP $version."
                       else
                           print_error "Gagal mengaktifkan ekstensi '$ext_name'. Pastikan paketnya (php${version}-${ext_name}) sudah terinstal."
                       fi
                       ;;
                    2) read -p "Masukkan nama ekstensi untuk dinonaktifkan: " ext_name
                       if phpdismod -v "$version" "$ext_name" 2>/dev/null; then
                           restart_php_fpm "$version"
                           print_success "Ekstensi '$ext_name' berhasil dinonaktifkan untuk PHP $version."
                       else
                           print_error "Gagal menonaktifkan ekstensi '$ext_name'."
                       fi
                       ;;
                    3) break ;;
                    *) print_error "Pilihan tidak valid." ;;
                esac
            done
            break
        else echo "Pilihan tidak valid."; fi
    done
}


# ... Fungsi lain (change_mariadb_root_pass, dll) tetap sama ...

change_mariadb_root_pass() {
    print_info "Mengubah Password Root MariaDB"
    read -sp "Masukkan password root MariaDB SAAT INI (jika lupa, cek instalasi awal): " OLD_PASS; echo ""
    read -sp "Masukkan password root MariaDB BARU: " NEW_PASS; echo ""
    read -sp "Konfirmasi password BARU: " NEW_PASS_CONFIRM; echo ""
    if [ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]; then print_error "Password baru tidak cocok."; return 1; fi
    if mysqladmin -u root -p"$OLD_PASS" password "$NEW_PASS"; then print_success "Password root MariaDB berhasil diubah."; else print_error "Gagal mengubah password. Pastikan password saat ini benar."; fi
}

change_pma_user_pass() {
    print_info "Mengubah Password User phpMyAdmin"
    read -sp "Untuk melanjutkan, masukkan password root MariaDB: " MARIADB_ROOT_PASS; echo ""
    read -p "Masukkan nama user phpMyAdmin yang akan diubah: " PMA_USER
    read -sp "Masukkan password BARU для user '$PMA_USER': " PMA_PASS; echo ""
    if mysql -u root -p"$MARIADB_ROOT_PASS" -e "ALTER USER '$PMA_USER'@'localhost' IDENTIFIED BY '$PMA_PASS'; FLUSH PRIVILEGES;"; then print_success "Password untuk user '$PMA_USER' berhasil diubah."; else print_error "Gagal mengubah password. Pastikan password root dan nama user benar."; fi
}

change_tfm_credentials() {
    print_info "Mengubah Kredensial Tiny File Manager"
    local tfm_file="/var/www/html/file-manager/index.php"
    if [ ! -f "$tfm_file" ]; then print_error "File Tiny File Manager tidak ditemukan di $tfm_file."; return 1; fi
    read -p "Masukkan username BARU untuk File Manager: " TFM_USER
    read -sp "Masukkan password BARU untuk File Manager: " TFM_PASS; echo ""
    local TFM_PASS_HASH=$(php -r "echo password_hash('$TFM_PASS', PASSWORD_DEFAULT);")
    sed -i "/^\s*'\w*'\s*=>/d" "$tfm_file"
    sed -i "/\$auth_users = array(/a \ \ \ \ '$TFM_USER' => '$TFM_PASS_HASH'," "$tfm_file"
    print_success "Kredensial File Manager berhasil diubah menjadi: $TFM_USER"
}

change_siab_port() {
    print_info "Mengubah Port Web SSH (Shell In A Box)"
    local siab_conf="/etc/default/shellinabox"; local apache_conf="/etc/apache2/conf-available/shellinabox.conf"
    read -p "Masukkan port BARU untuk Web SSH: " SIAB_PORT
    if ! [[ "$SIAB_PORT" =~ ^[0-9]+$ ]]; then print_error "Port harus berupa angka."; return 1; fi
    sed -i "s/^SHELLINABOX_PORT=.*/SHELLINABOX_PORT=${SIAB_PORT}/" "$siab_conf"
    sed -i "s#ProxyPass http://127.0.0.1:.*#ProxyPass http://127.0.0.1:${SIAB_PORT}/#" "$apache_conf"
    sed -i "s#ProxyPassReverse http://127.0.0.1:.*#ProxyPassReverse http://127.0.0.1:${SIAB_PORT}/#" "$apache_conf"
    print_info "Me-restart service terkait..."; systemctl restart shellinabox; systemctl reload apache2
    print_success "Port Web SSH berhasil diubah ke $SIAB_PORT. URL baru: http://<ip_server>/ssh/"
}


# -- TAMPILAN MENU --
main_menu() {
    while true; do
        echo ""; echo "======================================="
        echo "      Editor Konfigurasi Dashboard"; echo "======================================="
        echo "1. Instal Versi PHP Baru"; echo "2. Uninstall Versi PHP"
        echo "3. Kelola Ekstensi PHP"
        echo "---------------------------------------"
        echo "4. Ubah Password Root MariaDB"; echo "5. Ubah Password User phpMyAdmin"
        echo "6. Ubah Kredensial File Manager"; echo "7. Ubah Port Web SSH"
        echo "8. Keluar"; echo "======================================="
        read -p "Pilih opsi [1-8]: " choice

        case $choice in
            1) install_php_version ;;
            2) uninstall_php_version ;;
            3) manage_extensions ;;
            4) change_mariadb_root_pass ;;
            5) change_pma_user_pass ;;
            6) change_tfm_credentials ;;
            7) change_siab_port ;;
            8) break ;;
            *) print_error "Pilihan tidak valid." ;;
        esac
    done
}

# -- EKSEKUSI SKRIP --
check_root
main_menu
print_info "Selesai."