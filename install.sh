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

print_info() { log_message "INFO" "\e[34m🔵 INFO: $1\e[0m"; }
print_success() { log_message "SUCCESS" "\e[32m✅ SUKSES: $1\e[0m"; }
print_warning() { log_message "WARNING" "\e[33m⚠️ PERINGATAN: $1\e[0m"; }
print_error() { log_message "ERROR" "\e[31m❌ ERROR: $1\e[0m"; }

install_packages() {
    print_info "Menginstal paket: $@";
    # Mengatasi masalah debconf saat instalasi paket
    echo -e '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d
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
        systemctl restart "$1" || { print_error "Gagal merestart service $1."; exit 1; }
    else
        service "$1" restart || { print_error "Gagal merestart service $1."; exit 1; }
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
        read -p "Pilih mode instalasi [1] Otomatis (default) atau [2] Manual: " MODE_CHOICE < /dev/tty
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
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "CREATE USER '$PMA_USER'@'localhost' IDENTIFIED BY '$PMA_PASS';" || { print_error "Gagal membuat user phpMyAdmin."; exit 1; }
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON *.* TO '$PMA_USER'@'localhost' WITH GRANT OPTION;" || { print_error "Gagal memberikan hak akses ke user phpMyAdmin."; exit 1; }
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "FLUSH PRIVILEGES;" || { print_error "Gagal melakukan FLUSH PRIVILEGES."; exit 1; }

    print_info "Membuat database internal phpMyAdmin secara manual...";
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS phpmyadmin;" || { print_error "Gagal membuat database phpmyadmin."; exit 1; }
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

phase3_configure_apache() {
    print_info "FASE 3: Konfigurasi Apache..."
    # Aktifkan modul, tambahkan `|| true` jika sudah aktif tidak masalah
    a2enmod proxy proxy_http proxy_fcgi setenvif actions rewrite || true

    local sorted_versions
    # Urutkan versi dari yang terbaru ke terlama
    # Pastikan array PHP_VERSIONS_TO_INSTALL tidak kosong sebelum sort
    if [ ${#PHP_VERSIONS_TO_INSTALL[@]} -eq 0 ]; then
        print_error "Tidak ada versi PHP yang dipilih untuk instalasi. Tidak dapat mengatur PHP default Apache.";
        exit 1;
    fi
    IFS=$'\n' read -d '' -r -a sorted_versions < <(printf "%s\n" "${PHP_VERSIONS_TO_INSTALL[@]}" | sort -Vr) || { print_error "Gagal mengurutkan versi PHP."; exit 1; }
    
    local default_php_version=${sorted_versions[0]}
    local default_socket_path="/run/php/php${default_php_version}-fpm.sock"

    print_info "Mengatur PHP v${default_php_version} sebagai default untuk Dashboard di ${WEB_ROOT}..."
    cat <<EOF > /etc/apache2/conf-available/php-per-project.conf || { print_error "Gagal membuat php-per-project.conf."; exit 1; }
# Konfigurasi Default untuk Web Root (Dashboard)
# Otomatis diatur untuk menggunakan versi PHP terbaru yang diinstal: v${default_php_version}
<Directory ${WEB_ROOT}>
    Require all granted
    <FilesMatch \.php$>
        SetHandler "proxy:unix:${default_socket_path}|fcgi://localhost/"
    </FilesMatch>
</Directory>
EOF
    a2enconf php-per-project.conf || { print_error "Gagal mengaktifkan php-per-project.conf."; exit 1; }

    print_info "Memastikan phpMyAdmin menggunakan PHP-FPM v${default_php_version} dengan prioritas tinggi..."
    cat <<EOF > /etc/apache2/conf-available/phpmyadmin-override.conf || { print_error "Gagal membuat phpmyadmin-override.conf."; exit 1; }
# Override handler PHP-FPM untuk alias phpMyAdmin
# Ini memastikan phpMyAdmin menggunakan PHP yang benar (PHP-FPM)
# Ditempatkan di sini untuk memastikan prioritas yang tepat.
<Directory /usr/share/phpmyadmin>
    <FilesMatch \.php$>
        SetHandler "proxy:unix:${default_socket_path}|fcgi://localhost/"
    </FilesMatch>
</Directory>
EOF
    a2enconf phpmyadmin-override.conf || { print_error "Gagal mengaktifkan phpmyadmin-override.conf."; exit 1; }

    print_info "Mengisi database phpmyadmin dengan skema default..."
    mysql -u root -p"$MARIADB_ROOT_PASS" phpmyadmin < /usr/share/doc/phpmyadmin/examples/create_tables.sql || { print_error "Gagal mengisi database phpmyadmin."; exit 1; }
    print_success "Database phpmyadmin berhasil diinisialisasi."
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
    cat <<'EOF' > ${WEB_ROOT}/index.php
<?php
// PHP Version Manager & Real-time Server Monitoring Dashboard
define('WEB_ROOT', '/var/www/html'); 
define('STATE_FILE', __DIR__ . '/config/project_versions.json');
define('EXCLUDED_ITEMS', ['.', '..', 'index.php', 'config', 'assets', 'phpmyadmin', 'file-manager']);
function get_projects() { $all_items = scandir(WEB_ROOT); $projects = []; foreach ($all_items as $item) { if (!in_array($item, EXCLUDED_ITEMS) && is_dir(WEB_ROOT . '/' . $item)) { $projects[] = $item; } } return $projects; }
function get_installed_php_versions() { $sockets = glob('/run/php/php*-fpm.sock'); $versions = []; foreach ($sockets as $socket) { if (preg_match('/php(\d+\.\d+)-fpm\.sock$/', $socket, $matches)) { $versions[] = $matches[1]; } } rsort($versions, SORT_NUMERIC); return $versions; }
function get_project_states() { if (!file_exists(STATE_FILE)) return []; $json_data = file_get_contents(STATE_FILE); return json_decode($json_data, true) ?: []; }
function save_project_state($project, $version) { $states = get_project_states(); $states[$project] = $version; file_put_contents(STATE_FILE, json_encode($states, JSON_PRETTY_PRINT)); }
function getCpuCores() { if (PHP_OS_FAMILY === 'Windows') { $cores = getenv('NUMBER_OF_PROCESSORS'); return $cores ? intval($cores) : 1; } else { if (is_readable('/proc/cpuinfo')) { $cpuinfo = file_get_contents('/proc/cpuinfo'); preg_match_all('/^processor\s*:\s*\d+/m', $cpuinfo, $matches); return count($matches[0]) > 0 ? count($matches[0]) : 1; } } return 1; }
function getCpuInfo() { if (!function_exists('sys_getloadavg')) return false; $load = sys_getloadavg(); $cores = getCpuCores(); $percent = round(($load[0] / $cores) * 100); $percent_display = min($percent, 100); return ['load' => $load[0], 'cores' => $cores, 'percent' => $percent_display]; }
function formatBytes($bytes, $precision = 2) { if ($bytes === false || !is_numeric($bytes)) return "N/A"; $units = ['B', 'KB', 'MB', 'GB', 'TB']; $bytes = max($bytes, 0); $pow = floor(($bytes ? log($bytes) : 0) / log(1024)); $pow = min($pow, count($units) - 1); $bytes /= (1 << (10 * $pow)); return round($bytes, $precision) . ' ' . $units[$pow]; }
function getMemoryUsage() { $meminfo_path = '/proc/meminfo'; if (!is_readable($meminfo_path)) return false; $meminfo = file_get_contents($meminfo_path); preg_match('/MemTotal:\s+(\d+)/', $meminfo, $total); preg_match('/MemAvailable:\s+(\d+)/', $meminfo, $available); if (!isset($total[1]) || !isset($available[1])) return false; $total_mem_kb = $total[1]; $available_mem_kb = $available[1]; $used_mem_kb = $total_mem_kb - $available_mem_kb; $percent_used = ($total_mem_kb > 0) ? ($used_mem_kb / $total_mem_kb) * 100 : 0; return ['total' => $total_mem_kb * 1024, 'used' => $used_mem_kb * 1024, 'percent' => round($percent_used)]; }
function getStorageUsage() { $path = '/'; $total_space = @disk_total_space($path); $free_space = @disk_free_space($path); if ($total_space === false || $free_space === false) return false; $used_space = $total_space - $free_space; $percent_used = ($total_space > 0) ? ($used_space / $total_space) * 100 : 0; return ['total' => $total_space, 'used' => $used_space, 'percent' => round($percent_used)]; }
if (isset($_GET['json']) && $_GET['json'] == 'true') { header('Content-Type: application/json'); echo json_encode(['cpu' => getCpuInfo(), 'ram' => getMemoryUsage(), 'storage' => getStorageUsage()]); exit; }
$message = ''; $message_type = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['project']) && isset($_POST['php_version'])) { $project_to_set = escapeshellarg(trim($_POST['project'])); $version_to_set = escapeshellarg(trim($_POST['php_version'])); $command = "sudo /usr/local/bin/set_php_version.sh {$project_to_set} {$version_to_set} 2>&1"; $output = shell_exec($command); if (strpos(strtolower($output), 'error') === false) { save_project_state(trim($_POST['project']), trim($_POST['php_version'])); $message = "Sukses! $output"; $message_type = 'success'; } else { $message = "Error! $output"; $message_type = 'error'; } }
$projects = get_projects(); $php_versions = get_installed_php_versions(); $project_states = get_project_states(); $cpu_info = getCpuInfo(); $memory_usage = getMemoryUsage(); $storage_usage = getStorageUsage();
?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Server & Project Dashboard</title><script src="https://cdn.tailwindcss.com"></script></head><body class="bg-gray-100 text-gray-800 font-sans"><header class="bg-white shadow-md sticky top-0 z-10"><div class="container mx-auto px-6 py-4 flex justify-between items-center"><h1 class="text-2xl font-bold text-gray-800">Server Dashboard</h1><nav class="space-x-4"><a href="/file-manager/" target="_blank" class="text-indigo-600 hover:text-indigo-800 font-semibold">File Manager</a><a href="/phpmyadmin" target="_blank" class="text-indigo-600 hover:text-indigo-800 font-semibold">phpMyAdmin</a></nav></div></header><main class="container mx-auto px-6 py-8"><section id="resource-stats" class="mb-10"><h2 class="text-2xl font-bold text-center text-gray-700 mb-6">Status Sumber Daya Server</h2><div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"><div class="bg-white rounded-lg shadow p-5 flex flex-col"><h3 class="text-lg font-semibold text-gray-800 mb-3 flex items-center"><svg class="h-6 w-6 text-indigo-500 mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M8.25 3v1.5M4.5 8.25H3m18 0h-1.5M4.5 12H3m18 0h-1.5m-15 3.75H3m18 0h-1.5M8.25 19.5V21M12 3v1.5m0 15V21m3.75-18v1.5m0 15V21m-9-1.5h10.5a2.25 2.25 0 002.25-2.25V8.25a2.25 2.25 0 00-2.25-2.25H6.75A2.25 2.25 0 004.5 8.25v7.5A2.25 2.25 0 006.75 18z" /></svg>CPU</h3><?php if ($cpu_info): ?><div class="w-full bg-gray-200 rounded-full h-6"><div id="cpu-bar" class="bg-indigo-500 h-6 text-xs font-medium text-indigo-100 text-center p-1 leading-none rounded-full" style="width: <?php echo $cpu_info['percent']; ?>%"><?php echo $cpu_info['percent']; ?>%</div></div><div class="flex justify-between text-sm text-gray-500 mt-2"><span id="cpu-text">Load: <?php echo $cpu_info['load']; ?></span><span>Cores: <?php echo $cpu_info['cores']; ?></span></div><?php else: ?><p class="text-red-500 font-semibold">Tidak Didukung.</p><?php endif; ?></div><div class="bg-white rounded-lg shadow p-5 flex flex-col"><h3 class="text-lg font-semibold text-gray-800 mb-3 flex items-center"><svg class="h-6 w-6 text-green-500 mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M8.25 7.5V6.108c0-1.135.845-2.098 1.976-2.192.373-.03.748-.03 1.125 0 1.131.094 1.976 1.057 1.976 2.192V7.5M8.25 7.5h7.5M8.25 7.5V9a.75.75 0 01-.75.75H5.25A.75.75 0 014.5 9V7.5m8.25 0V9a.75.75 0 00.75.75h2.25a.75.75 0 00.75-.75V7.5M12 10.5h.008v.008H12v-.008zM12 15h.008v.008H12v-.008zm0 2.25h.008v.008H12v-.008zM9.75 15h.008v.008H9.75v-.008zm0 2.25h.008v.008H9.75v-.008zM7.5 15h.008v.008H7.5v-.008zm0 2.25h.008v.008H7.5v-.008zm6.75-4.5h.008v.008h-.008v-.008zm0 2.25h.008v.008h-.008v-.008z" /></svg>RAM</h3><?php if ($memory_usage): ?><div class="w-full bg-gray-200 rounded-full h-6"><div id="ram-bar" class="bg-green-500 h-6 text-xs font-medium text-green-100 text-center p-1 leading-none rounded-full" style="width: <?php echo $memory_usage['percent']; ?>%"><?php echo $memory_usage['percent']; ?>%</div></div><div class="flex justify-between text-sm text-gray-500 mt-2"><span id="ram-text">Digunakan: <?php echo formatBytes($memory_usage['used']); ?></span><span>Total: <?php echo formatBytes($memory_usage['total']); ?></span></div><?php else: ?><p class="text-red-500 font-semibold">Tidak Didukung.</p><?php endif; ?></div><div class="bg-white rounded-lg shadow p-5 flex flex-col"><h3 class="text-lg font-semibold text-gray-800 mb-3 flex items-center"><svg class="h-6 w-6 text-sky-500 mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" /></svg>Penyimpanan</h3><?php if ($storage_usage): ?><div class="w-full bg-gray-200 rounded-full h-6"><div id="storage-bar" class="bg-sky-500 h-6 text-xs font-medium text-sky-100 text-center p-1 leading-none rounded-full" style="width: <?php echo $storage_usage['percent']; ?>%"><?php echo $storage_usage['percent']; ?>%</div></div><div class="flex justify-between text-sm text-gray-500 mt-2"><span id="storage-text">Digunakan: <?php echo formatBytes($storage_usage['used']); ?></span><span>Total: <?php echo formatBytes($storage_usage['total']); ?></span></div><?php else: ?><p class="text-red-500 font-semibold">Tidak Didukung.</p><?php endif; ?></div></div></section><hr class="my-10 border-gray-200"><section id="project-management"><?php if ($message): ?><div class="mb-6 p-4 rounded-md <?php echo $message_type === 'success' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'; ?>"><?php echo htmlspecialchars($message); ?></div><?php endif; ?><div class="bg-white rounded-lg shadow-lg"><div class="p-6 border-b border-gray-200"><h2 class="text-xl font-semibold">Manajemen Proyek</h2><p class="text-gray-600 mt-1">Atur versi PHP untuk setiap proyek.</p></div><div class="overflow-x-auto"><table class="min-w-full text-left"><thead class="bg-gray-50 border-b border-gray-200"><tr><th class="px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">Nama Proyek</th><th class="px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">Versi PHP</th><th class="px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">Aksi</th></tr></thead><tbody class="divide-y divide-gray-200">
                <?php if (empty($projects)): ?><tr><td colspan="3" class="px-6 py-12 text-center text-gray-500"><p>Belum ada proyek.</p><p class="text-sm">Buat folder baru di `<?php echo WEB_ROOT; ?>`.</p></td></tr><?php else: ?>
                <?php foreach ($projects as $project): ?><?php $current_version = $project_states[$project] ?? 'Default'; ?><tr class="hover:bg-gray-50"><td class="px-6 py-4 whitespace-nowrap"><div class="flex items-center"><svg class="h-6 w-6 text-yellow-500 mr-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z" /></svg><a href="/<?php echo htmlspecialchars($project); ?>" target="_blank" class="font-medium text-indigo-600 hover:text-indigo-900"><?php echo htmlspecialchars($project); ?></a></div></td><td class="px-6 py-4 whitespace-nowrap"><span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full <?php echo $current_version !== 'Default' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'; ?>"><?php echo htmlspecialchars($current_version); ?></span></td><td class="px-6 py-4 whitespace-nowrap text-sm font-medium"><form method="POST" action="index.php" class="flex items-center gap-2"><input type="hidden" name="project" value="<?php echo htmlspecialchars($project); ?>"><select name="php_version" class="block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"><?php foreach ($php_versions as $version): ?><option value="<?php echo $version; ?>" <?php echo ($project_states[$project] ?? '') === $version ? 'selected' : ''; ?>>PHP <?php echo $version; ?></option><?php endforeach; ?></select><button type="submit" class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">Simpan</button></form></td></tr><?php endforeach; ?><?php endif; ?>
                </tbody></table></div></div></section></main><footer class="text-center text-gray-500 text-sm py-6 mt-4"><p>Dashboard &copy; <?php echo date("Y"); ?></p></footer><script>
                    function formatBytesJS(bytes, decimals = 2) {if (!+bytes) return '0 B';const k = 1024;const dm = decimals < 0 ? 0 : decimals;const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];const i = Math.floor(Math.log(bytes) / Math.log(k));return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`;}
                    async function updateStats() {
                        try {
                            const response = await fetch('index.php?json=true', { cache: "no-store" });
                            if (!response.ok) return;
                            const data = await response.json();
                            if (data.cpu) {const el = document.getElementById('cpu-bar');if (el) { el.style.width = data.cpu.percent + '%'; el.textContent = data.cpu.percent + '%'; }const txt = document.getElementById('cpu-text');if (txt) txt.textContent = 'Load: ' + data.cpu.load;}
                            if (data.ram) {const el = document.getElementById('ram-bar');if (el) { el.style.width = data.ram.percent + '%'; el.textContent = data.ram.percent + '%'; }const txt = document.getElementById('ram-text');if (txt) txt.textContent = 'Digunakan: ' + formatBytesJS(data.ram.used);}
                            if (data.storage) {const el = document.getElementById('storage-bar');if (el) { el.style.width = data.storage.percent + '%'; el.textContent = data.storage.percent + '%'; }const txt = document.getElementById('storage-text');if (txt) txt.textContent = 'Digunakan: ' + formatBytesJS(data.storage.used);}
                        } catch (error) {console.error('Gagal memperbarui status:', error);}
                    }
                    setInterval(updateStats, 2000);
                </script></body></html>
EOF
}

phase5_finalize() {
    print_info "FASE 5: Finalisasi...";
    mkdir -p ${WEB_ROOT}/config || { print_error "Gagal membuat direktori config."; exit 1; }
    touch ${WEB_ROOT}/config/project_versions.json || { print_error "Gagal membuat project_versions.json."; exit 1; }
    chown -R www-data:www-data ${WEB_ROOT} || { print_error "Gagal mengubah kepemilikan direktori web root."; exit 1; }
    restart_service apache2
    apt-get autoremove -y || true
}

display_summary() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}' | xargs)
    clear;
    print_success "INSTALASI SELESAI!"
    echo "======================================================================" | tee -a "$LOG_FILE"; printf "\n" | tee -a "$LOG_FILE"
    printf "  Dashboard: \e[1;36mhttp://%s/\e[0m\n\n" "${IP_ADDRESS}" | tee -a "$LOG_FILE"
    printf "  Akses Alat Bantu:\n";
    printf "+-----------------+------------------------------------------+\n" | tee -a "$LOG_FILE"
    printf "| \e[1;32m%s\e[0m        | \e[1;36m%s\e[0m                                  |\n" "ALAT" "DETAIL" | tee -a "$LOG_FILE"
    printf "+-----------------+------------------------------------------+\n" | tee -a "$LOG_FILE"
    printf "| File Manager    | URL: http://%s/file-manager/           |\n" "${IP_ADDRESS}" | tee -a "$LOG_FILE"
    printf "|                 | User: %-36s |\n" "${TFM_USER}" | tee -a "$LOG_FILE";
    printf "|                 | Pass: %-36s |\n" "${TFM_PASS}" | tee -a "$LOG_FILE"
    printf "+-----------------+------------------------------------------+\n" | tee -a "$LOG_FILE"
    printf "| phpMyAdmin      | URL: http://%s/phpmyadmin              |\n" "${IP_ADDRESS}" | tee -a "$LOG_FILE"
    printf "|                 | User: %-36s |\n" "${PMA_USER}" | tee -a "$LOG_FILE";
    printf "|                 | Pass: %-36s |\n" "${PMA_PASS}" | tee -a "$LOG_FILE"
    printf "+-----------------+------------------------------------------+\n" | tee -a "$LOG_FILE"
    printf "| DB Root         | User: root                               |\n" | tee -a "$LOG_FILE"
    printf "|                 | Pass: %-36s |\n" "${MARIADB_ROOT_PASS}" | tee -a "$LOG_FILE"
    printf "+-----------------+------------------------------------------+\n\n" | tee -a "$LOG_FILE"
    
    # Menambahkan info akses dummy project phpinfo
    printf "  Project Testing PHPInfo: \e[1;36mhttp://%s/test_project_phpinfo/\e[0m\n\n" "${IP_ADDRESS}" | tee -a "$LOG_FILE"
    
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
        read -p "Pilih tindakan: [1] Ulang dari Awal (bersihkan semua) atau [2] Keluar: " resume_choice < /dev/tty
        case $resume_choice in
            1) silent_cleanup ;;
            *) echo "Instalasi dibatalkan."; exit 0 ;;
        esac
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
    echo '<?php echo "Hello World dari proyek PHP!"; ?>' > "${WEB_ROOT}/test_project_hello/index.php" || { print_error "Gagal membuat file index.php di dummy project 'test_project_hello'."; exit 1; }
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