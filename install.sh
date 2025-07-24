#!/bin/bash

# ==============================================================================
#   Skrip Otomatis Pemasangan Dashboard Server & Manajemen Multi-PHP (Final Lengkap)
# ==============================================================================
#   Menggabungkan semua fitur: Mode Ganda (Interaktif/Non-Interaktif),
#   Deteksi systemd, Rollback, PHP Default Otomatis, dan semua alat bantu.
#
#   VERSI PERBAIKAN:
#   - FIX: Koneksi phpMyAdmin dengan mengkonfigurasi handler PHP-FPM secara eksplisit dan lebih andal.
#   - FIX: Tautan ke phpMyAdmin di index.php diubah menjadi huruf kecil.
#   - FIX: Metode penulisan kredensial Tiny File Manager dibuat lebih andal.
#   - FIX: Masalah 'set -e' dengan penanganan error yang lebih baik dan konfigurasi phpMyAdmin manual.
#   - FIX: Error "Conf phpmyadmin does not exist!" dengan menghapus aktivasi alias yang redundan.
#   - FIX: Error "Can't change dir to '/var/lib/mysql/'" dengan memastikan direktori data MariaDB ada.
#   - BARU: Penambahan logging otomatis ke file untuk debugging yang lebih mudah.
#   - BARU: Penambahan dua dummy project ('test_project_phpinfo', 'test_project_hello') untuk pengujian multi-PHP.
#   - FIX: Deteksi error yang lebih granular di fase konfigurasi Apache.
# ==============================================================================

# Keluar segera jika ada perintah yang gagal
set -e # Aktifkan set -e untuk penghentian skrip saat ada error

# -- VARIABEL GLOBAL --
export DEBIAN_FRONTEND=noninteractive
WEB_ROOT="/var/www/html"
LOCK_FILE="/tmp/.dashboard_install_lock"
PHP_VERSIONS_DEFAULT=("8.3" "7.4") # Default diurutkan dari baru ke lama
PHP_VERSIONS_TO_INSTALL=()
PHP_VERSIONS_STABLE=("8.3" "8.2" "8.1" "8.0" "7.4" "5.6")
LOG_FILE="/var/log/dashboard_install_$(date +%Y%m%d_%H%M%S).log" # Nama file log unik

# -- FUNGSI BANTUAN (Dengan Logging) --
log_message() {
    local type="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$type] $message" | tee -a "$LOG_FILE" # Cetak ke konsol dan log file
}

print_info() { log_message "INFO" "$1"; }
print_success() { log_message "SUCCESS" "$1"; }
print_warning() { log_message "WARNING" "$1"; }
print_error() { log_message "ERROR" "$1"; }

install_packages() {
    print_info "Menginstal paket: $@";
    # Mengatasi masalah debconf saat instalasi paket
    echo '#!/bin/sh' > /usr/sbin/policy-rc.d
    echo 'exit 0' >> /usr/sbin/policy-rc.d
    chmod +x /usr/sbin/policy-rc.d
    apt-get install -y "$@" || { print_error "Gagal menginstal paket: $@"; exit 1; }
    rm -f /usr/sbin/policy-rc.d
}

# -- FUNGSI ROLLBACK & CLEANUP --
silent_cleanup() {
    print_info "Menjalankan pembersihan otomatis...";
    trap - ERR # Menonaktifkan trap ERR sementara untuk cleanup
    if [ "${USE_SYSTEMD:-yes}" = "yes" ]; then
        systemctl stop apache2 mariadb || true
    else
        service apache2 stop || true
        service mariadb stop || true
    fi
    apt-get purge --auto-remove -y apache2* mariadb-* phpmyadmin "php*" || true
    rm -f /etc/apt/sources.list.d/php.list
    rm -f /usr/share/keyrings/deb.sury.org-php.gpg
    rm -f /usr/local/bin/set_php_version.sh
    rm -f /etc/sudoers.d/www-data-php-manager
    rm -f /etc/apache2/conf-available/php-per-project.conf
    rm -f /etc/apache2/conf-available/phpmyadmin-handler.conf
    rm -f /etc/apache2/conf-available/phpmyadmin-override.conf # Hapus file override juga
    rm -rf /var/www/html/*
    rm -rf /var/lib/mysql
    apt-get autoremove -y || true
    print_success "Pembersihan selesai."
    trap cleanup_on_error ERR # Mengaktifkan kembali trap ERR
}

cleanup_on_error() {
    print_error "Instalasi gagal pada baris $BASH_LINENO. Periksa log: $LOG_FILE";
    silent_cleanup;
    print_error "Rollback Selesai.";
    exit 1;
}

# -- FUNGSI MANAJEMEN SERVICE --
start_service() {
    print_info "Memulai service: $1"
    if [ "$USE_SYSTEMD" = "yes" ]; then
        systemctl start "$1" || { print_error "Gagal memulai service $1."; exit 1; }
    else
        service "$1" start || { print_error "Gagal memulai service $1."; exit 1; }
    fi
}
enable_service() {
    print_info "Mengaktifkan service saat boot: $1"
    if [ "$USE_SYSTEMD" = "yes" ]; then
        systemctl enable "$1" || { print_error "Gagal mengaktifkan service $1."; exit 1; }
    else
        update-rc.d "$1" defaults || { print_error "Gagal mengaktifkan service $1."; exit 1; }
    fi
}
restart_service() {
    print_info "Merestart service: $1"
    if [ "$USE_SYSTEMD" = "yes" ]; then
        systemctl restart "$1" || { print_error "Gagal merestart PHP-FPM."; exit 1; }
    else
        service "$1" restart || { print_error "Gagal merestart PHP-FPM."; exit 1; }
    fi
}

# -- FUNGSI-FUNGSI INSTALASI --
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_error "Skrip ini harus dijalankan sebagai root.";
        exit 1;
    fi;
}
generate_random_string() {
    openssl rand -base64 12 | tr -dc A-Za-z0-9 | head -c 12
}
add_php_repository() {
    print_info "Menambahkan repositori PHP dari packages.sury.org...";
    install_packages lsb-release ca-certificates apt-transport-https software-properties-common gnupg
    curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg || { print_error "Gagal mengunduh GPG key PHP."; exit 1; }
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | tee -a /etc/apt/sources.list.d/php.list || { print_error "Gagal menambahkan repositori PHP."; exit 1; }
    apt-get update || { print_error "Gagal mengupdate apt repository setelah menambahkan PHP PPA."; exit 1; }
}

get_setup_choices() {
    if [ "$#" -gt 0 ]; then
        print_info "Menjalankan dalam mode non-interaktif..."
        INSTALL_MODE="$1"; USE_SYSTEMD="$2"; IFS=',' read -r -a PHP_VERSIONS_TO_INSTALL <<< "$3"
        MARIADB_ROOT_PASS="$4"; PMA_USER="$5"; PMA_PASS="$6"; TFM_USER="$7"; TFM_PASS="$8"
    else
        clear;
        echo "======================================================================" | tee -a "$LOG_FILE"
        echo "      Selamat Datang di Skrip Pemasangan Dashboard Otomatis" | tee -a "$LOG_FILE"
        echo "======================================================================" | tee -a "$LOG_FILE"
        print_warning "Pastikan skrip ini dijalankan pada sistem Debian 12 yang bersih."; echo "" | tee -a "$LOG_FILE"
        read -p "Pilih tindakan: [1] Ulang dari Awal (bersihkan semua) atau [2] Keluar: " MODE_CHOICE < /dev/tty
        INSTALL_MODE=${MODE_CHOICE:-1}

        if [ -d /run/systemd/system ]; then
            USE_SYSTEMD="yes"
            print_info "Deteksi systemd berhasil."
        else
            read -p "Lingkungan non-systemd terdeteksi. Apakah ini benar? [y/N]: " SYSTEMD_CHOICE < /dev/tty
            [[ "$SYSTEMD_CHOICE" =~ ^[Yy]$ ]] && USE_SYSTEMD="no" || USE_SYSTEMD="yes"
        fi

        local AVAILABLE_VERSIONS=("${PHP_VERSIONS_STABLE[@]}");
        if [ "$INSTALL_MODE" = "2" ]; then
            echo "-----------------------------------------------------" | tee -a "$LOG_FILE";
            PS3="Pilih versi PHP (pisahkan dengan spasi): ";
            select v in "${AVAILABLE_VERSIONS[@]}"; do
                if [ -n "$REPLY" ]; then
                    for choice in $REPLY; do
                        # Pastikan pilihan valid
                        if (( choice > 0 && choice <= ${#AVAILABLE_VERSIONS[@]} )); then
                            PHP_VERSIONS_TO_INSTALL+=("${AVAILABLE_VERSIONS[$choice-1]}");
                        else
                            print_warning "Pilihan PHP $choice tidak valid, diabaikan."
                        fi
                    done
                    break;
                else
                    echo "Pilihan tidak valid." | tee -a "$LOG_FILE";
                 portátil;
                fi;
            done < /dev/tty
        else
            PHP_VERSIONS_TO_INSTALL=("${PHP_VERSIONS_DEFAULT[@]}")
        fi

        if [ ${#PHP_VERSIONS_TO_INSTALL[@]} -eq 0 ]; then
            print_error "Tidak ada PHP dipilih.";
            exit 1;
        fi

        if [ "$INSTALL_MODE" = "2" ]; then
            print_info "Mode Manual: Masukkan detail kredensial."
            read -p "Pass root MariaDB [Enter=acak]: " MARIADB_ROOT_PASS < /dev/tty
            read -p "User phpMyAdmin [Enter=pma_user]: " PMA_USER < /dev/tty
            read -p "Pass user phpMyAdmin [Enter=acak]: " PMA_PASS < /dev/tty
            read -p "User File Manager [Enter=fm_admin]: " TFM_USER < /dev/tty
            read -sp "Pass File Manager [Enter=acak]: " TFM_PASS < /dev/tty; echo "" | tee -a "$LOG_FILE"
        fi
        MARIADB_ROOT_PASS=${MARIADB_ROOT_PASS:-$(generate_random_string)};
        PMA_USER=${PMA_USER:-pma_user};
        PMA_PASS=${PMA_PASS:-$(generate_random_string)}
        TFM_USER=${TFM_USER:-fm_admin};
        TFM_PASS=${TFM_PASS:-$(generate_random_string)}
    fi
    print_info "Versi PHP yang akan diinstal: ${PHP_VERSIONS_TO_INSTALL[*]}"
}

phase1_setup_stack() {
    print_info "FASE 1: Instalasi Dasar...";
    apt-get update && apt-get upgrade -y || { print_error "Gagal update atau upgrade sistem."; exit 1; }
    install_packages apache2 mariadb-server mariadb-client curl wget bc

    # Pastikan direktori data MariaDB ada dan memiliki izin yang benar
    print_info "Memastikan direktori data MariaDB (/var/lib/mysql) ada dan benar..."
    mkdir -p /var/lib/mysql || { print_error "Gagal membuat direktori /var/lib/mysql."; exit 1; }
    chown -R mysql:mysql /var/lib/mysql || { print_error "Gagal mengatur kepemilikan /var/lib/mysql."; exit 1; }
    chmod 755 /var/lib/mysql || { print_error "Gagal mengatur izin /var/lib/mysql."; exit 1; }
    # Inisialisasi direktori data MariaDB jika kosong (penting untuk fresh install)
    if [ -z "$(ls -A /var/lib/mysql)" ]; then
        print_info "Menginisialisasi direktori data MariaDB..."
        mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql || { print_error "Gagal menginisialisasi database MariaDB."; exit 1; }
    fi

    start_service apache2
    enable_service apache2
    start_service mariadb
    enable_service mariadb

    print_info "Mengamankan MariaDB...";
    mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MARIADB_ROOT_PASS');" || { print_error "Gagal mengatur password root MariaDB."; exit 1; }
    mysql -e "DELETE FROM mysql.user WHERE User='';";
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');";
    mysql -e "DROP DATABASE IF EXISTS test;";
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';";
    mysql -e "FLUSH PRIVILEGES;";

    print_info "Membuat user phpMyAdmin...";
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "DROP USER IF EXISTS '$PMA_USER'@'localhost';" || { print_warning "Gagal menghapus user phpMyAdmin jika ada. Melanjutkan."; }
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "CREATE USER '$PMA_USER'@'localhost' IDENTIFIED BY '$PMA_PASS';" || { print_error "Gagal membuat user phpMyAdmin."; exit 1; }
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON *.* TO '$PMA_USER'@'localhost' WITH GRANT OPTION;" || { print_error "Gagal memberikan hak akses ke user phpMyAdmin."; exit 1; }
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "FLUSH PRIVILEGES;" || { print_error "Gagal melakukan FLUSH PRIVILEGES."; exit 1; }

    print_info "Membuat database internal phpMyAdmin secara manual...";
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS phpmyadmin;" || { print_error "Gagal membuat database phpmyadmin."; exit 1; }
}

phase3_configure_apache() {
    print_info "FASE 3: Konfigurasi Apache..."
    # Aktifkan modul yang diperlukan untuk PHP dan Apache
    a2enmod proxy proxy_http proxy_fcgi setenvif rewrite || true
    
    # Urutkan versi dari yang terbaru ke terlama
    # Pastikan array PHP_VERSIONS_TO_INSTALL tidak kosong sebelum sort
    if [ ${#PHP_VERSIONS_TO_INSTALL[@]} -eq 0 ]; then
        print_error "Tidak ada versi PHP yang dipilih untuk instalasi. Tidak dapat mengatur PHP default Apache.";
        exit 1;
    fi

    # Check if the first element is empty, which can happen if the string parsing results in an empty first element
    if [ -z "${PHP_VERSIONS_TO_INSTALL[0]}" ]; then
        print_error "PHP_VERSIONS_TO_INSTALL array is empty or malformed. Debugging needed."
        exit 1
    fi
    
    # Dapatkan versi PHP default (versi tertinggi)
    local sorted_versions_string
    sorted_versions_string=$(printf "%s\n" "${PHP_VERSIONS_TO_INSTALL[@]}" | sort -rn) || { print_error "Gagal mengurutkan versi PHP."; exit 1; }

    # Convert the newline-separated string back into an array
    IFS=$'\n' read -r -a sorted_versions <<< "$sorted_versions_string"

    local default_php_version=${sorted_versions[0]}
    local default_socket_path="/run/php/php${default_php_version}-fpm.sock"
    
    # Periksa apakah socket PHP-FPM ada
    if [ ! -e "$default_socket_path" ]; then
        print_error "Socket PHP-FPM untuk versi ${default_php_version} tidak ditemukan di ${default_socket_path}. Memastikan PHP-FPM berjalan..."
        # Restart PHP-FPM service
        if [ "$USE_SYSTEMD" = "yes" ]; then
            systemctl restart "php${default_php_version}-fpm" || { print_error "Gagal merestart PHP-FPM."; exit 1; }
        else
            service "php${default_php_version}-fpm" restart || { print_error "Gagal merestart PHP-FPM."; exit 1; }
        fi
        # Tunggu sebentar
        sleep 3
        # Periksa lagi
        if [ ! -e "$default_socket_path" ]; then
            print_error "Socket PHP-FPM masih tidak ditemukan setelah restart. Periksa instalasi PHP.";
            exit 1;
        fi
    fi
    
    print_info "Mengatur PHP v${default_php_version} sebagai default untuk Dashboard di ${WEB_ROOT}..."
    
    # Process and copy the Apache config templates
    local php_dashboard_template_content
    php_dashboard_template_content=$(cat /vagrant/php-dashboard.conf.template)
    php_dashboard_template_content=$(echo "$php_dashboard_template_content" | sed "s|\${WEB_ROOT}|${WEB_ROOT}|g")
    php_dashboard_template_content=$(echo "$php_dashboard_template_content" | sed "s|\${default_php_version}|${default_php_version}|g")
    php_dashboard_template_content=$(echo "$php_dashboard_template_content" | sed "s|\${default_socket_path}|${default_socket_path}|g")
    echo "$php_dashboard_template_content" > /etc/apache2/conf-available/php-dashboard.conf || { print_error "Gagal menulis php-dashboard.conf."; exit 1; }
    
    # Aktifkan konfigurasi
    a2enconf php-dashboard.conf || { print_error "Gagal mengaktifkan php-dashboard.conf."; exit 1; }
    
    local default_site_template_content
    default_site_template_content=$(cat /vagrant/000-default.conf.template)
    default_site_template_content=$(echo "$default_site_template_content" | sed "s|\${WEB_ROOT}|${WEB_ROOT}|g")
    echo "$default_site_template_content" > /etc/apache2/sites-available/000-default.conf || { print_error "Gagal menulis 000-default.conf."; exit 1; }
    
    print_info "Mengisi database phpmyadmin dengan skema default..."
    mysql -u root -p"$MARIADB_ROOT_PASS" phpmyadmin < /usr/share/doc/phpmyadmin/examples/create_tables.sql || { print_error "Gagal mengisi database phpmyadmin."; exit 1; }
    print_success "Database phpmyadmin berhasil diinisialisasi."
}

phase2_install_multi_php() {
    print_info "FASE 2: Instalasi PHP...";
    add_php_repository

    for version in "${PHP_VERSIONS_TO_INSTALL[@]}"; do
        print_info "Menginstal PHP ${version}-FPM...";
        local extensions=("mysql" "xml" "curl" "zip" "mbstring" "bcmath" "soap" "intl" "gd" "cli") # Tambahkan 'cli'
        if (( $(echo "$version < 8.0" | bc -l) )); then extensions+=("json"); fi
        local packages_to_install=("php${version}" "php${version}-fpm");
        for ext in "${extensions[@]}"; do
            packages_to_install+=("php${version}-${ext}");
        done
        install_packages "${packages_to_install[@]}"
    done

    print_info "Menginstal phpMyAdmin dan mengaturnya untuk tidak dikonfigurasi secara otomatis...";
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect " | debconf-set-selections
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean false" | debconf-set-selections
    install_packages phpmyadmin
    apt-mark hold phpmyadmin # Mencegah phpmyadmin diupdate/dikonfigurasi ulang oleh apt
}


phase4_install_tools() {
    print_info "FASE 4: Memasang Alat Bantu..."
    rm -f ${WEB_ROOT}/index.html

    if [ -f /vagrant/set_php_version.sh ]; then
        cp /vagrant/set_php_version.sh /usr/local/bin/set_php_version.sh || { print_error "Gagal menyalin set_php_version.sh dari /vagrant."; exit 1; }
    elif [ -f ./set_php_version.sh ]; then
        cp ./set_php_version.sh /usr/local/bin/set_php_version.sh || { print_error "Gagal menyalin set_php_version.sh dari direktori saat ini."; exit 1; }
    else
        print_error "set_php_version.sh tidak ditemukan di /vagrant atau direktori saat ini. Skrip tidak bisa dilanjutkan."
        exit 1
    fi
    chmod +x /usr/local/bin/set_php_version.sh || { print_error "Gagal mengubah izin set_php_version.sh."; exit 1; }
    echo "www-data ALL=(ALL) NOPASSWD: /usr/local/bin/set_php_version.sh" | tee -a /etc/sudoers.d/www-data-php-manager || { print_error "Gagal menambahkan konfigurasi sudoers untuk www-data."; exit 1; }
    
    mkdir -p ${WEB_ROOT} || { print_error "Gagal membuat direktori ${WEB_ROOT}."; exit 1; }
    cd ${WEB_ROOT} || { print_error "Gagal masuk ke direktori ${WEB_ROOT}."; exit 1; }
    wget -qO tinyfilemanager.php https://raw.githubusercontent.com/prasathmani/tinyfilemanager/master/tinyfilemanager.php || { print_error "Gagal mengunduh tinyfilemanager.php."; exit 1; }
    mkdir -p file-manager || { print_error "Gagal membuat direktori file-manager."; exit 1; }
    mv tinyfilemanager.php file-manager/index.php || { print_error "Gagal memindahkan tinyfilemanager.php."; exit 1; }
    
    print_info "Mengatur kredensial Tiny File Manager..."
    local TFM_TARGET_FILE="${WEB_ROOT}/file-manager/index.php"
    local TFM_PASS_HASH=$(php -r "echo password_hash('$TFM_PASS', PASSWORD_DEFAULT);" 2>/dev/null)
    
    if [ -z "$TFM_PASS_HASH" ]; then
        print_warning "Gagal menghasilkan hash password PHP untuk Tiny File Manager. Mungkin PHP CLI belum sepenuhnya siap atau ada masalah. Menggunakan password plain-text (TIDAK AMAN) atau Anda harus mengkonfigurasi manual."
        TFM_PASS_HASH="$TFM_PASS"
    fi

    sed -i "s#^// \$auth_users = array(#\$auth_users = array(#g" "$TFM_TARGET_FILE" || { print_error "Gagal mengaktifkan auth_users di TFM."; exit 1; }
    sed -i "/'admin'\s*=>/d" "$TFM_TARGET_FILE" || true
    sed -i "/'user'\s*=>/d" "$TFM_TARGET_FILE" || true
    sed -i "/^\$auth_users = array(/a \    '${TFM_USER}' => '${TFM_PASS_HASH}'," "$TFM_TARGET_FILE" || { print_error "Gagal menambahkan user TFM."; exit 1; }
    sed -i "s#\$root_path = \$_SERVER\['DOCUMENT_ROOT'\];#\$root_path = '${WEB_ROOT}';#g" "$TFM_TARGET_FILE" || { print_error "Gagal mengatur root_path di TFM."; exit 1; }

    print_info "Membuat file dashboard utama 'index.php'..."
    # Copy the template file instead of echoing content
    cp /vagrant/index.php.template ${WEB_ROOT}/index.php || { print_error "Gagal menyalin index.php.template ke ${WEB_ROOT}/index.php."; exit 1; }
}

phase5_finalize() {
    print_info "FASE 5: Finalisasi...";
    mkdir -p ${WEB_ROOT}/config || { print_error "Gagal membuat direktori config."; exit 1; }
    touch ${WEB_ROOT}/config/project_versions.json || { print_error "Gagal membuat project_versions.json."; exit 1; }
    chown -R www-data:www-data ${WEB_ROOT} || { print_error "Gagal mengubah kepemilikan direktori web root."; exit 1; }
    
    # Buat symlink untuk phpMyAdmin
    if [ -d "/usr/share/phpmyadmin" ] && [ ! -d "${WEB_ROOT}/phpmyadmin" ] && [ ! -L "${WEB_ROOT}/phpmyadmin" ]; then
        ln -s /usr/share/phpmyadmin ${WEB_ROOT}/phpmyadmin || { print_error "Gagal membuat symlink untuk phpMyAdmin."; exit 1; }
        print_info "Symlink phpMyAdmin berhasil dibuat."
    elif [ -L "${WEB_ROOT}/phpmyadmin" ]; then
        print_info "Symlink phpMyAdmin sudah ada."
    elif [ -d "${WEB_ROOT}/phpmyadmin" ]; then
        print_info "Direktori phpMyAdmin sudah ada."
    else
        print_warning "Direktori sumber phpMyAdmin tidak ditemukan di /usr/share/phpmyadmin."
    fi
    
    # Hapus konfigurasi phpmyadmin.conf yang lama jika ada
    if [ -f "/etc/apache2/conf-available/phpmyadmin.conf" ]; then
        rm -f /etc/apache2/conf-available/phpmyadmin.conf
        print_info "File konfigurasi phpmyadmin.conf telah dihapus."
    fi
    if [ -L "/etc/apache2/conf-enabled/phpmyadmin.conf" ]; then
        rm -f /etc/apache2/conf-enabled/phpmyadmin.conf
        print_info "Link konfigurasi phpmyadmin.conf telah dihapus."
    fi
    
    # Konfigurasi phpMyAdmin sudah dilakukan di php-dashboard.conf
    print_info "Konfigurasi phpMyAdmin sudah dilakukan di php-dashboard.conf."
    
    restart_service apache2
    apt-get autoremove -y || true
}

display_summary() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}' | xargs)
    clear;
    print_success "INSTALASI SELESAI!"
    echo "======================================================================" | tee -a "$LOG_FILE"; printf "\n" | tee -a "$LOG_FILE"
    printf "  Dashboard: \e[1;36mhttp://%s/\e[0m\n\n" "${IP_ADDRESS}" | tee -a "$LOG_FILE"
    printf "  Akses Alat Bantu:\n";
    printf "+-----------------+------------------------------------------+\n" | tee -a "$LOG_FILE"
    printf "| \e[1;32m%s\e[0m        | \e[1;36m%s\e[0m                                  |\n" "ALAT" "DETAIL" | tee -a "$LOG_FILE"
    printf "+-----------------+------------------------------------------+\n" | tee -a "$LOG_FILE"
    printf "| File Manager    | URL: http://%s/file-manager/           |\n" "${IP_ADDRESS}" | tee -a "$LOG_FILE"
    printf "|                 | User: %-36s |\n" "${TFM_USER}" | tee -a "$LOG_FILE";
    printf "|                 | Pass: %-36s |\n" "${TFM_PASS}" | tee -a "$LOG_FILE"
    printf "+-----------------+------------------------------------------+\n" | tee -a "$LOG_FILE"
    printf "| phpMyAdmin      | URL: http://%s/phpmyadmin              |\n" "${IP_ADDRESS}" | tee -a "$LOG_FILE"
    printf "|                 | User: %-36s |\n" "${PMA_USER}" | tee -a "$LOG_FILE";
    printf "|                 | Pass: %-36s |\n" "${PMA_PASS}" | tee -a "$LOG_FILE"
    printf "+-----------------+------------------------------------------+\n" | tee -a "$LOG_FILE"
    printf "| DB Root         | User: root                               |\n" | tee -a "$LOG_FILE"
    printf "|                 | Pass: %-36s |\n" "${MARIADB_ROOT_PASS}" | tee -a "$LOG_FILE"
    printf "+-----------------+------------------------------------------+\n\n" | tee -a "$LOG_FILE"
    
    # Menambahkan info akses dummy project phpinfo
    printf "  Project Testing PHPInfo: \e[1;36mhttp://%s/test_project_phpinfo/\e[0m\n\n" "${IP_ADDRESS}" | tee -a "$LOG_FILE"
    
    print_warning "Catat semua kredensial ini dan simpan di tempat yang aman."
    echo "======================================================================" | tee -a "$LOG_FILE"
}

main() {
    # Buat file log sebelum memulai operasi
    touch "$LOG_FILE" || { echo "Gagal membuat file log: $LOG_FILE. Keluar."; exit 1; }
    echo "--- Memulai Skrip Instalasi Dashboard Server ---" | tee -a "$LOG_FILE"
    echo "Log akan disimpan di: $LOG_FILE" | tee -a "$LOG_FILE"
    
    trap cleanup_on_error ERR;
    check_root
    if [ -f "$LOCK_FILE" ]; then
        print_warning "Ditemukan sisa instalasi yang mungkin gagal sebelumnya."
        if [ "$#" -gt 0 ]; then # Non-interactive mode (arguments provided)
            silent_cleanup # Automatically clean up
        else # Interactive mode
            read -p "Pilih tindakan: [1] Ulang dari Awal (bersihkan semua) atau [2] Keluar: " resume_choice < /dev/tty
            case $resume_choice in
                1) silent_cleanup ;;
                *) echo "Instalasi dibatalkan."; exit 0 ;;
            esac
        fi
    fi
    
    touch "$LOCK_FILE" || { print_error "Gagal membuat file kunci instalasi."; exit 1; }
    get_setup_choices "$@"
    
    phase1_setup_stack
    phase2_install_multi_php
    phase3_configure_apache
    phase4_install_tools
    
    # --- Tambahan untuk dummy project PHPInfo dan Hello World ---
    print_info "Membuat dummy project 'test_project_phpinfo' untuk pengujian PHPInfo..."
    mkdir -p "${WEB_ROOT}/test_project_phpinfo" || { print_error "Gagal membuat direktori dummy project 'test_project_phpinfo'."; exit 1; }
    echo '<?php phpinfo(); ?>' > "${WEB_ROOT}/test_project_phpinfo/index.php" || { print_error "Gagal membuat file phpinfo.php di dummy project 'test_project_phpinfo'."; exit 1; }
    chown -R www-data:www-data "${WEB_ROOT}/test_project_phpinfo" || { print_error "Gagal mengatur kepemilikan dummy project 'test_project_phpinfo'."; exit 1; }
    print_success "Dummy project 'test_project_phpinfo' berhasil dibuat."

    print_info "Membuat dummy project 'test_project_hello' untuk pengujian sederhana..."
    mkdir -p "${WEB_ROOT}/test_project_hello" || { print_error "Gagal membuat direktori dummy project 'test_project_hello'."; exit 1; }
    echo '<?php echo "Hello World from PHP project!"; ?>' > "${WEB_ROOT}/test_project_hello/index.php" || { print_error "Gagal membuat file index.php di dummy project 'test_project_hello'."; exit 1; }
    chown -R www-data:www-data "${WEB_ROOT}/test_project_hello" || { print_error "Gagal mengatur kepemilikan dummy project 'test_project_hello'."; exit 1; }
    print_success "Dummy project 'test_project_hello' berhasil dibuat."
    # --- Akhir tambahan dummy projects ---

    phase5_finalize
    
    trap - ERR;
    rm -f "$LOCK_FILE" || print_warning "Gagal menghapus file kunci instalasi.";
    display_summary
    echo "--- Skrip Instalasi Selesai ---" | tee -a "$LOG_FILE"
}

main "$@"