#!/bin/bash

# ==============================================================================
#   Skrip Otomatis Pemasangan Dashboard Server & Manajemen Multi-PHP (Revisi Final)
# ==============================================================================
#   FITUR: Instalasi Ekstensi Cerdas, Pemilihan PHP, Mode Otomatis/Manual, Deteksi systemd, Rollback.
# ==============================================================================

# Keluar segera jika ada perintah yang gagal
set -e

# -- VARIABEL GLOBAL --
export DEBIAN_FRONTEND=noninteractive
WEB_ROOT="/var/www/html"
PHP_VERSIONS_DEFAULT=("7.4" "8.2")
PHP_VERSIONS_TO_INSTALL=()

# -- FUNGSI BANTUAN --
print_info() { echo -e "\n\e[34m🔵 INFO: $1\e[0m"; }
print_success() { echo -e "\e[32m✅ SUKSES: $1\e[0m"; }
print_warning() { echo -e "\e[33m⚠️ PERINGATAN: $1\e[0m"; }
print_error() { echo -e "\e[31m❌ ERROR: $1\e[0m"; }

# -- FUNGSI ROLLBACK --
cleanup_on_error() {
    print_error "Instalasi gagal pada salah satu langkah."
    print_info "Memulai proses rollback otomatis..."
    trap - ERR
    if [ "$USE_SYSTEMD" = "yes" ]; then systemctl stop apache2 mariadb shellinabox || true; else service apache2 stop || true; service mariadb stop || true; service shellinabox stop || true; fi
    apt-get purge --auto-remove -y apache2* mariadb-* phpmyadmin shellinabox "php*" || true
    rm -f /etc/apt/sources.list.d/ondrej-php.list
    rm -f /usr/share/keyrings/ondrej-php.gpg
    rm -f /usr/local/bin/set_php_version.sh
    rm -f /etc/sudoers.d/www-data-php-manager
    rm -f /etc/apache2/conf-available/php-per-project.conf
    rm -f /etc/apache2/conf-available/shellinabox.conf
    rm -rf /var/www/html/*
    rm -rf /var/lib/mysql
    apt-get autoremove -y
    print_error "Rollback Selesai. Sistem telah dikembalikan ke kondisi sebelum instalasi."
    exit 1
}

# -- FUNGSI MANAJEMEN SERVICE --
start_service() { if [ "$USE_SYSTEMD" = "yes" ]; then systemctl start "$1"; else service "$1" start; fi; }
enable_service() { if [ "$USE_SYSTEMD" = "yes" ]; then systemctl enable "$1"; else update-rc.d "$1" defaults; fi; }
restart_service() { if [ "$USE_SYSTEMD" = "yes" ]; then systemctl restart "$1"; else service "$1" restart; fi; }

# -- FUNGSI-FUNGSI INSTALASI --

check_root() {
    if [ "$(id -u)" != "0" ]; then
       print_error "Skrip ini harus dijalankan sebagai root atau dengan sudo."
       exit 1
    fi
}

generate_random_string() {
    openssl rand -base64 12
}

add_ppa_manually() {
    print_info "Menambahkan PPA 'ppa:ondrej/php' secara manual..."
    apt-get install -y gpg curl
    local key_url="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x14AA40EC0831756756D7F66C4F4EA0AAE5267A6C"
    local key_path="/usr/share/keyrings/ondrej-php.gpg"
    curl -sSL "$key_url" | gpg --dearmor -o "$key_path"
    
    local source_file="/etc/apt/sources.list.d/ondrej-php.list"
    echo "deb [signed-by=${key_path}] https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main" > "$source_file"
    
    print_info "Memperbarui daftar paket setelah menambahkan PPA..."
    apt-get update
}

get_setup_choices() {
    clear
    echo "======================================================================"
    echo "      Selamat Datang di Skrip Pemasangan Dashboard Otomatis"
    echo "======================================================================"
    print_warning "Pastikan skrip ini dijalankan pada sistem Debian 12 yang bersih."
    echo ""

    read -p "Pilih mode instalasi [1] Otomatis (default) atau [2] Manual: " MODE_CHOICE < /dev/tty
    INSTALL_MODE=${MODE_CHOICE:-1}

    if [ -d /run/systemd/system ]; then
        USE_SYSTEMD="yes"
        print_info "Deteksi systemd berhasil. Menggunakan mode systemd."
    else
        read -p "Lingkungan ini sepertinya tidak menggunakan systemd. Apakah ini benar? [y/N]: " SYSTEMD_CHOICE < /dev/tty
        [[ "$SYSTEMD_CHOICE" =~ ^[Yy]$ ]] && USE_SYSTEMD="no" || USE_SYSTEMD="yes"
    fi
    
    apt-get update
    apt-get install -y ca-certificates software-properties-common
    add_ppa_manually
    
    LATEST_VERSIONS=($(apt-cache search --names-only '^php[0-9]\.[0-9]$' | awk '{print $1}' | sed 's/php//' | sort -V -r | head -n 5))
    AVAILABLE_VERSIONS=("${LATEST_VERSIONS[@]}")
    [[ " ${AVAILABLE_VERSIONS[*]} " =~ " 7.4 " ]] || AVAILABLE_VERSIONS+=("7.4")
    [[ " ${AVAILABLE_VERSIONS[*]} " =~ " 5.6 " ]] || AVAILABLE_VERSIONS+=("5.6")

    if [ "$INSTALL_MODE" = "2" ]; then
        echo "-----------------------------------------------------"
        PS3="Pilih satu atau lebih versi PHP untuk diinstal (pisahkan dengan spasi): "
        select version in "${AVAILABLE_VERSIONS[@]}"; do
            if [ -n "$REPLY" ]; then
                for choice in $REPLY; do PHP_VERSIONS_TO_INSTALL+=("${AVAILABLE_VERSIONS[$choice-1]}"); done
                break
            else echo "Pilihan tidak valid. Coba lagi."; fi
        done < /dev/tty
    else
        print_info "Mode Otomatis: Pilih versi PHP atau tekan Enter untuk default (${PHP_VERSIONS_DEFAULT[*]})."
        echo "Versi yang tersedia: ${AVAILABLE_VERSIONS[*]}"
        read -p "Masukkan pilihan Anda (pisahkan dengan spasi) atau tekan Enter: " PHP_CHOICE < /dev/tty
        if [ -z "$PHP_CHOICE" ]; then PHP_VERSIONS_TO_INSTALL=("${PHP_VERSIONS_DEFAULT[@]}"); else PHP_VERSIONS_TO_INSTALL=($PHP_CHOICE); fi
    fi

    if [ ${#PHP_VERSIONS_TO_INSTALL[@]} -eq 0 ]; then print_error "Tidak ada versi PHP yang dipilih."; exit 1; fi
    print_info "Versi PHP yang akan diinstal: ${PHP_VERSIONS_TO_INSTALL[*]}"

    if [ "$INSTALL_MODE" = "2" ]; then
        print_info "Mode Manual: Silakan masukkan detail kredensial di bawah ini."
        read -p "Masukkan password root MariaDB [Enter untuk default acak]: " MARIADB_ROOT_PASS < /dev/tty
        read -p "Masukkan nama user phpMyAdmin [Enter untuk default: pma_user]: " PMA_USER < /dev/tty
        read -p "Masukkan password user phpMyAdmin [Enter untuk default acak]: " PMA_PASS < /dev/tty
        read -p "Masukkan username File Manager [Enter untuk default: fm_admin]: " TFM_USER < /dev/tty
        read -sp "Masukkan password File Manager [Enter untuk default acak]: " TFM_PASS < /dev/tty
        echo ""; read -p "Masukkan port Web SSH [Default: 4201]: " SIAB_PORT < /dev/tty
    fi

    MARIADB_ROOT_PASS=${MARIADB_ROOT_PASS:-$(generate_random_string)}
    PMA_USER=${PMA_USER:-pma_user}
    PMA_PASS=${PMA_PASS:-$(generate_random_string)}
    TFM_USER=${TFM_USER:-fm_admin}
    TFM_PASS=${TFM_PASS:-$(generate_random_string)}
    SIAB_PORT=${SIAB_PORT:-4201}
}

phase1_setup_stack() {
    print_info "FASE 1: Memulai Instalasi Dasar..."
    apt-get upgrade -y
    apt-get install -y apache2 mariadb-server mariadb-client curl wget
    
    print_info "Menjalankan dan mengaktifkan service Apache2 & MariaDB..."
    start_service apache2 && enable_service apache2
    start_service mariadb && enable_service mariadb

    print_info "Mengamankan instalasi MariaDB..."
    mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MARIADB_ROOT_PASS');"
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mysql -e "FLUSH PRIVILEGES;"

    print_info "Membuat user database untuk phpMyAdmin..."
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "CREATE USER '$PMA_USER'@'localhost' IDENTIFIED BY '$PMA_PASS';"
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON *.* TO '$PMA_USER'@'localhost' WITH GRANT OPTION;"
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "FLUSH PRIVILEGES;"
}

# ==============================================================================
# FUNGSI phase2_install_multi_php DIUBAH DI SINI
# ==============================================================================
phase2_install_multi_php() {
    print_info "FASE 2: Menginstal Versi PHP yang Dipilih..."
    for version in "${PHP_VERSIONS_TO_INSTALL[@]}"; do
        print_info "Menginstal PHP ${version}-FPM dan ekstensinya..."
        
        # Daftar ekstensi dasar yang umum untuk semua versi
        local extensions=("mysql" "xml" "curl" "zip" "mbstring" "bcmath" "soap" "intl" "gd")
        
        # Logika Cerdas: Untuk versi PHP < 8.0, tambahkan 'json' secara manual
        # bc adalah program kalkulator, -l memuat library matematika
        if (( $(echo "$version < 8.0" | bc -l) )); then
            extensions+=("json")
        fi
        
        # Membangun daftar paket lengkap untuk diinstal
        local packages_to_install=()
        packages_to_install+=("php${version}")
        packages_to_install+=("php${version}-fpm")
        for ext in "${extensions[@]}"; do
            packages_to_install+=("php${version}-${ext}")
        done
        
        # Menjalankan instalasi
        apt-get install -y "${packages_to_install[@]}"
    done

    print_info "Menginstal phpMyAdmin..."
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    apt-get install -y phpmyadmin
}

# Sisa skrip tidak berubah...

phase3_configure_apache() {
    print_info "FASE 3: Melakukan Konfigurasi Apache..."
    a2enmod proxy proxy_http proxy_fcgi setenvif actions rewrite proxy_wstunnel
    a2enconf phpmyadmin
    touch /etc/apache2/conf-available/php-per-project.conf
    a2enconf php-per-project.conf
    cat <<EOF > /etc/apache2/conf-available/shellinabox.conf
<Location /ssh/>
    ProxyPass http://127.0.0.1:$SIAB_PORT/
    ProxyPassReverse http://127.0.0.1:$SIAB_PORT/
</Location>
EOF
    a2enconf shellinabox.conf
}

phase4_install_tools() {
    print_info "FASE 4: Memasang Alat Bantu..."
    cat <<'EOF' > /usr/local/bin/set_php_version.sh
#!/bin/bash
set -e
if [ "$#" -ne 2 ]; then echo "Penggunaan: $0 <nama_proyek> <versi_php>"; exit 1; fi
PROJECT_NAME=$1; PHP_VERSION=$2; WEB_ROOT="/var/www/html"; APACHE_CONFIG_FILE="/etc/apache2/conf-available/php-per-project.conf"
PROJECT_PATH="${WEB_ROOT}/${PROJECT_NAME}"; SOCKET_PATH="/run/php/php${PHP_VERSION}-fpm.sock"
if [ ! -d "${PROJECT_PATH}" ]; then echo "Error: Folder proyek tidak ditemukan di ${PROJECT_PATH}"; exit 1; fi
if [ ! -e "${SOCKET_PATH}" ]; then echo "Error: Socket PHP-FPM untuk versi ${PHP_VERSION} tidak ditemukan."; exit 1; fi
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
    if [ -d /run/systemd/system ]; then systemctl reload apache2; else service apache2 reload; fi
    echo "Apache berhasil di-reload."
else
    echo "ERROR: Konfigurasi Apache baru mengandung error. Apache tidak di-reload."; exit 1;
fi
exit 0
EOF
    chmod +x /usr/local/bin/set_php_version.sh
    echo "www-data ALL=(ALL) NOPASSWD: /usr/local/bin/set_php_version.sh" > /etc/sudoers.d/www-data-php-manager
    apt-get install -y shellinabox
    cat <<EOF > /etc/default/shellinabox
SHELLINABOX_PORT=${SIAB_PORT}
SHELLINABOX_ARGS="--no-beep --disable-ssl-menu -s /:LOGIN"
SHELLINABOX_BIND_IP="127.0.0.1"
EOF
    cd ${WEB_ROOT}
    wget -qO tinyfilemanager.php https://raw.githubusercontent.com/prasathmani/tinyfilemanager/master/tinyfilemanager.php
    mkdir -p file-manager
    mv tinyfilemanager.php file-manager/index.php
    TFM_PASS_HASH=$(php -r "echo password_hash('$TFM_PASS', PASSWORD_DEFAULT);")
    sed -i "s#^// \$auth_users = array(#\$auth_users = array(#g" "${WEB_ROOT}/file-manager/index.php"
    sed -i "s#'admin' => '\$2y\$10\$KVMiF8xX25eQOXYN225m9uC4S3A9H2x2B.aQ.Y3oZ4a.aQ.Y3oZ4a'#'${TFM_USER}' => '${TFM_PASS_HASH}'#g" "${WEB_ROOT}/file-manager/index.php"
    sed -i "/'user'\s*=>/d" "${WEB_ROOT}/file-manager/index.php"
    sed -i "s#\$root_path = \$_SERVER\['DOCUMENT_ROOT'\];#\$root_path = '${WEB_ROOT}';#g" "${WEB_ROOT}/file-manager/index.php"
    wget -qO ${WEB_ROOT}/index.php https://gist.githubusercontent.com/dandhany/60787d559e8656641ab3a30c5e933190/raw/f1df843e9e7616900f9ac13725b36bb339474771/index.php
}

phase5_finalize() {
    print_info "FASE 5: Menyelesaikan Instalasi..."
    mkdir -p ${WEB_ROOT}/config
    touch ${WEB_ROOT}/config/project_versions.json
    chown -R www-data:www-data ${WEB_ROOT}
    restart_service apache2
    restart_service shellinabox
    apt-get autoremove -y
}

display_summary() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    clear
    print_success "SELURUH PROSES INSTALASI DAN KONFIGURASI SELESAI!"
    echo "======================================================================"
    printf "\n"
    printf "  Dashboard Utama Anda siap diakses di:\n"
    printf "  ➡️  \e[1;36mhttp://%s/\e[0m\n" "${IP_ADDRESS}"
    printf "\n"
    printf "  Berikut adalah detail akses untuk alat bantu lainnya:\n"
    printf "+--------------------------+-------------------------------------------------+\n"
    printf "| \e[1;32m%s\e[0m                 | \e[1;36m%s\e[0m  |\n" "ALAT" "DETAIL"
    printf "+--------------------------+-------------------------------------------------+\n"
    printf "| Web SSH (ShellInABox)    | URL: http://%s/ssh/                      |\n" "${IP_ADDRESS}"
    printf "|                          | Login: Gunakan username & password sistem Linux Anda. |\n"
    printf "+--------------------------+-------------------------------------------------+\n"
    printf "| File Manager             | URL: http://%s/file-manager/             |\n" "${IP_ADDRESS}"
    printf "|                          | Username: %-35s |\n" "${TFM_USER}"
    printf "|                          | Password: %-35s |\n" "${TFM_PASS}"
    printf "+--------------------------+-------------------------------------------------+\n"
    printf "| Database (phpMyAdmin)    | URL: http://%s/phpMyAdmin              |\n" "${IP_ADDRESS}"
    printf "|                          | Username: %-35s |\n" "${PMA_USER}"
    printf "|                          | Password: %-35s |\n" "${PMA_PASS}"
    printf "+--------------------------+-------------------------------------------------+\n"
    printf "| Database (Root)          | Username: root                                  |\n"
    printf "|                          | Password: %-35s |\n" "${MARIADB_ROOT_PASS}"
    printf "+--------------------------+-------------------------------------------------+\n\n"
    print_warning "Untuk keamanan, catat semua kredensial ini dan simpan di tempat yang aman."
    echo "======================================================================"
}

# -- EKSEKUSI SKRIP --
main() {
    trap cleanup_on_error ERR
    check_root
    get_setup_choices
    phase1_setup_stack
    phase2_install_multi_php
    phase3_configure_apache
    phase4_install_tools
    phase5_finalize
    trap - ERR
    display_summary
}

main