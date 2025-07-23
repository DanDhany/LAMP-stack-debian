#!/bin/bash

# ==============================================================================
#   Skrip Otomatis Pemasangan Dashboard Server & Manajemen Multi-PHP (Versi Fleksibel)
# ==============================================================================
#   FITUR: Mode Otomatis/Manual, Deteksi systemd, dan Rollback Otomatis.
# ==============================================================================

# Keluar segera jika ada perintah yang gagal
set -e

# -- VARIABEL GLOBAL --
export DEBIAN_FRONTEND=noninteractive
WEB_ROOT="/var/www/html"
PHP_VERSIONS=("7.4" "8.2")

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
    systemctl stop apache2 mariadb shellinabox || true
    apt-get purge --auto-remove -y apache2* mariadb-* phpmyadmin shellinabox "php7.4*" "php8.2*" || true
    if command -v add-apt-repository &> /dev/null; then add-apt-repository --remove ppa:ondrej/php -y || true; fi
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
start_service() {
    if [ "$USE_SYSTEMD" = "yes" ]; then
        systemctl start "$1"
    else
        service "$1" start
    fi
}

enable_service() {
    if [ "$USE_SYSTEMD" = "yes" ]; then
        systemctl enable "$1"
    else
        update-rc.d "$1" defaults
    fi
}

restart_service() {
    if [ "$USE_SYSTEMD" = "yes" ]; then
        systemctl restart "$1"
    else
        service "$1" restart
    fi
}

reload_service() {
    if [ "$USE_SYSTEMD" = "yes" ]; then
        systemctl reload "$1"
    else
        service "$1" reload
    fi
}


# -- FUNGSI-FUNGSI INSTALASI --

check_root() {
    if [ "$(id -u)" != "0" ]; then
       print_error "Skrip ini harus dijalankan sebagai root atau dengan sudo."
       exit 1
    fi
}

# Fungsi untuk menghasilkan string acak
generate_random_string() {
    openssl rand -base64 12
}

get_user_input() {
    clear
    echo "======================================================================"
    echo "      Selamat Datang di Skrip Pemasangan Dashboard Otomatis"
    echo "======================================================================"
    print_warning "Pastikan skrip ini dijalankan pada sistem Debian 12 yang bersih."
    echo ""

    # Pilihan mode instalasi
    read -p "Pilih mode instalasi [1] Otomatis (default) atau [2] Manual: " MODE_CHOICE
    INSTALL_MODE=${MODE_CHOICE:-1}

    # Pilihan systemd
    # Cek apakah PID 1 adalah systemd
    if [ -d /run/systemd/system ]; then
        USE_SYSTEMD="yes"
        print_info "Deteksi systemd berhasil. Menggunakan mode systemd."
    else
        read -p "Lingkungan ini sepertinya tidak menggunakan systemd. Apakah ini benar? [y/N]: " SYSTEMD_CHOICE
        if [[ "$SYSTEMD_CHOICE" =~ ^[Yy]$ ]]; then
            USE_SYSTEMD="no"
        else
            USE_SYSTEMD="yes"
        fi
    fi

    # Pengaturan kredensial berdasarkan mode
    if [ "$INSTALL_MODE" = "2" ]; then # Mode Manual
        print_info "Mode Manual dipilih. Silakan masukkan detail di bawah ini."
        read -p "Masukkan password root MariaDB [Enter untuk default acak]: " MARIADB_ROOT_PASS
        read -p "Masukkan nama user phpMyAdmin [Enter untuk default: pma_user]: " PMA_USER
        read -p "Masukkan password user phpMyAdmin [Enter untuk default acak]: " PMA_PASS
        read -p "Masukkan username File Manager [Enter untuk default: fm_admin]: " TFM_USER
        read -sp "Masukkan password File Manager [Enter untuk default acak]: " TFM_PASS
        echo ""
        read -p "Masukkan port Web SSH [Default: 4201]: " SIAB_PORT
    fi

    # Set default untuk input yang kosong atau mode otomatis
    MARIADB_ROOT_PASS=${MARIADB_ROOT_PASS:-$(generate_random_string)}
    PMA_USER=${PMA_USER:-pma_user}
    PMA_PASS=${PMA_PASS:-$(generate_random_string)}
    TFM_USER=${TFM_USER:-fm_admin}
    TFM_PASS=${TFM_PASS:-$(generate_random_string)}
    SIAB_PORT=${SIAB_PORT:-4201}
}

phase1_setup_stack() {
    print_info "FASE 1: Memulai Instalasi Dasar..."
    apt-get update && apt-get upgrade -y
    apt-get install -y apache2 mariadb-server mariadb-client software-properties-common curl wget
    
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

phase2_install_multi_php() {
    print_info "FASE 2: Memulai Instalasi Multi-PHP..."
    add-apt-repository ppa:ondrej/php -y
    apt-get update

    for version in "${PHP_VERSIONS[@]}"; do
        print_info "Menginstal PHP ${version}-FPM dan ekstensinya..."
        apt-get install -y php${version} php${version}-fpm php${version}-mysql php${version}-xml php${version}-curl php${version}-zip php${version}-mbstring php${version}-json php${version}-bcmath php${version}-soap php${version}-intl php${version}-gd
    done

    print_info "Menginstal phpMyAdmin..."
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    apt-get install -y phpmyadmin
}

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
    get_user_input
    phase1_setup_stack
    phase2_install_multi_php
    phase3_configure_apache
    phase4_install_tools
    phase5_finalize
    trap - ERR
    display_summary
}

main