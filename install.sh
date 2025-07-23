#!/bin/bash

# ==============================================================================
#   Skrip Otomatis Pemasangan Dashboard Server & Manajemen Multi-PHP (Final Lengkap)
# ==============================================================================
#   Menggabungkan semua fitur: Mode Ganda (Interaktif/Non-Interaktif),
#   Deteksi systemd, Rollback, PHP Default Otomatis, dan semua alat bantu.
# ==============================================================================

# Keluar segera jika ada perintah yang gagal
set -x

# -- VARIABEL GLOBAL --
export DEBIAN_FRONTEND=noninteractive
WEB_ROOT="/var/www/html"
LOCK_FILE="/tmp/.dashboard_install_lock"
PHP_VERSIONS_DEFAULT=("8.3" "7.4") # Default diurutkan dari baru ke lama
PHP_VERSIONS_TO_INSTALL=()
PHP_VERSIONS_STABLE=("8.3" "8.2" "8.1" "8.0" "7.4" "5.6")

# -- FUNGSI BANTUAN --
print_info() { echo -e "\n\e[34m🔵 INFO: $1\e[0m"; }
print_success() { echo -e "\e[32m✅ SUKSES: $1\e[0m"; }
print_warning() { echo -e "\e[33m⚠️ PERINGATAN: $1\e[0m"; }
print_error() { echo -e "\e[31m❌ ERROR: $1\e[0m"; }

install_packages() {
    print_info "Menginstal paket: $@"; echo -e '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
    apt-get install -y "$@" || true; rm -f /usr/sbin/policy-rc.d
}

# -- FUNGSI ROLLBACK & CLEANUP --
silent_cleanup() {
    print_info "Menjalankan pembersihan otomatis..."; trap - ERR
    if [ "${USE_SYSTEMD:-yes}" = "yes" ]; then systemctl stop apache2 mariadb || true; else service apache2 stop || true; service mariadb stop || true; fi
    apt-get purge --auto-remove -y apache2* mariadb-* phpmyadmin "php*" || true
    rm -f /etc/apt/sources.list.d/php.list; rm -f /usr/share/keyrings/deb.sury.org-php.gpg
    rm -f /usr/local/bin/set_php_version.sh; rm -f /etc/sudoers.d/www-data-php-manager
    rm -f /etc/apache2/conf-available/php-per-project.conf; rm -rf /var/www/html/*; rm -rf /var/lib/mysql
    apt-get autoremove -y; print_success "Pembersihan selesai."
}
cleanup_on_error() { print_error "Instalasi gagal."; silent_cleanup; print_error "Rollback Selesai."; exit 1; }

# -- FUNGSI MANAJEMEN SERVICE --
start_service() { if [ "$USE_SYSTEMD" = "yes" ]; then systemctl start "$1"; else service "$1" start; fi; }
enable_service() { if [ "$USE_SYSTEMD" = "yes" ]; then systemctl enable "$1"; else update-rc.d "$1" defaults; fi; }
restart_service() { if [ "$USE_SYSTEMD" = "yes" ]; then systemctl restart "$1"; else service "$1" restart; fi; }

# -- FUNGSI-FUNGSI INSTALASI --
check_root() { if [ "$(id -u)" != "0" ]; then print_error "Skrip ini harus dijalankan sebagai root."; exit 1; fi; }
generate_random_string() { openssl rand -base64 12; }
add_php_repository() {
    print_info "Menambahkan repositori PHP dari packages.sury.org..."; install_packages lsb-release ca-certificates apt-transport-https software-properties-common gnupg
    curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
    apt-get update
}

get_setup_choices() {
    if [ "$#" -gt 0 ]; then
        print_info "Menjalankan dalam mode non-interaktif..."
        INSTALL_MODE="$1"; USE_SYSTEMD="$2"; IFS=',' read -r -a PHP_VERSIONS_TO_INSTALL <<< "$3"
        MARIADB_ROOT_PASS="$4"; PMA_USER="$5"; PMA_PASS="$6"; TFM_USER="$7"; TFM_PASS="$8"
    else
        clear; echo "======================================================================"
        echo "      Selamat Datang di Skrip Pemasangan Dashboard Otomatis"; echo "======================================================================"
        print_warning "Pastikan skrip ini dijalankan pada sistem Debian 12 yang bersih."; echo ""
        read -p "Pilih mode instalasi [1] Otomatis (default) atau [2] Manual: " MODE_CHOICE < /dev/tty
        INSTALL_MODE=${MODE_CHOICE:-1}
        if [ -d /run/systemd/system ]; then USE_SYSTEMD="yes"; print_info "Deteksi systemd berhasil."; else read -p "Lingkungan non-systemd terdeteksi. Apakah ini benar? [y/N]: " SYSTEMD_CHOICE < /dev/tty; [[ "$SYSTEMD_CHOICE" =~ ^[Yy]$ ]] && USE_SYSTEMD="no" || USE_SYSTEMD="yes"; fi
        local AVAILABLE_VERSIONS=("${PHP_VERSIONS_STABLE[@]}");
        if [ "$INSTALL_MODE" = "2" ]; then
            echo "-----------------------------------------------------"; PS3="Pilih versi PHP (pisahkan dengan spasi): "; select v in "${AVAILABLE_VERSIONS[@]}"; do if [ -n "$REPLY" ]; then for choice in $REPLY; do PHP_VERSIONS_TO_INSTALL+=("${AVAILABLE_VERSIONS[$choice-1]}"); done; break; else echo "Pilihan tidak valid."; fi; done < /dev/tty
        else
             PHP_VERSIONS_TO_INSTALL=("${PHP_VERSIONS_DEFAULT[@]}")
        fi
        if [ ${#PHP_VERSIONS_TO_INSTALL[@]} -eq 0 ]; then print_error "Tidak ada PHP dipilih."; exit 1; fi
        if [ "$INSTALL_MODE" = "2" ]; then
            print_info "Mode Manual: Masukkan detail kredensial."
            read -p "Pass root MariaDB [Enter=acak]: " MARIADB_ROOT_PASS < /dev/tty
            read -p "User phpMyAdmin [Enter=pma_user]: " PMA_USER < /dev/tty
            read -p "Pass user phpMyAdmin [Enter=acak]: " PMA_PASS < /dev/tty
            read -p "User File Manager [Enter=fm_admin]: " TFM_USER < /dev/tty
            read -sp "Pass File Manager [Enter=acak]: " TFM_PASS < /dev/tty; echo ""
        fi
        MARIADB_ROOT_PASS=${MARIADB_ROOT_PASS:-$(generate_random_string)}; PMA_USER=${PMA_USER:-pma_user}; PMA_PASS=${PMA_PASS:-$(generate_random_string)}
        TFM_USER=${TFM_USER:-fm_admin}; TFM_PASS=${TFM_PASS:-$(generate_random_string)}
    fi
    print_info "Versi PHP yang akan diinstal: ${PHP_VERSIONS_TO_INSTALL[*]}"
}

phase1_setup_stack() {
    print_info "FASE 1: Instalasi Dasar..."; apt-get update && apt-get upgrade -y
    install_packages apache2 mariadb-server mariadb-client curl wget bc
    start_service apache2 && enable_service apache2; start_service mariadb && enable_service mariadb
    print_info "Mengamankan MariaDB..."; mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MARIADB_ROOT_PASS');"
    mysql -e "DELETE FROM mysql.user WHERE User='';"; mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"; mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"; mysql -e "FLUSH PRIVILEGES;"
    print_info "Membuat user phpMyAdmin..."; mysql -u root -p"$MARIADB_ROOT_PASS" -e "CREATE USER '$PMA_USER'@'localhost' IDENTIFIED BY '$PMA_PASS';"
    mysql -u root -p"$MARIADB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON *.* TO '$PMA_USER'@'localhost' WITH GRANT OPTION;"; mysql -u root -p"$MARIADB_ROOT_PASS" -e "FLUSH PRIVILEGES;"
}

phase2_install_multi_php() {
    print_info "FASE 2: Instalasi PHP..."; add_php_repository
    for version in "${PHP_VERSIONS_TO_INSTALL[@]}"; do
        print_info "Menginstal PHP ${version}-FPM..."; local extensions=("mysql" "xml" "curl" "zip" "mbstring" "bcmath" "soap" "intl" "gd")
        if (( $(echo "$version < 8.0" | bc -l) )); then extensions+=("json"); fi
        local packages_to_install=("php${version}" "php${version}-fpm"); for ext in "${extensions[@]}"; do packages_to_install+=("php${version}-${ext}"); done
        install_packages "${packages_to_install[@]}"
    done
    print_info "Menginstal phpMyAdmin..."; echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    install_packages phpmyadmin
}

phase3_configure_apache() {
    print_info "FASE 3: Konfigurasi Apache..."
    a2enmod proxy proxy_http proxy_fcgi setenvif actions rewrite || true
    a2enconf phpmyadmin || true
    
    local sorted_versions
    IFS=$'\n' read -d '' -r -a sorted_versions < <(printf "%s\n" "${PHP_VERSIONS_TO_INSTALL[@]}" | sort -Vr)
    local default_php_version=${sorted_versions[0]}
    local default_socket_path="/run/php/php${default_php_version}-fpm.sock"

    print_info "Mengatur PHP v${default_php_version} sebagai default untuk Dashboard di ${WEB_ROOT}..."
    cat <<EOF > /etc/apache2/conf-available/php-per-project.conf
# Konfigurasi Default untuk Web Root (Dashboard)
# Otomatis diatur untuk menggunakan versi PHP terbaru yang diinstal: v${default_php_version}
<Directory ${WEB_ROOT}>
    Require all granted
    <FilesMatch \.php$>
        SetHandler "proxy:unix:${default_socket_path}|fcgi://localhost/"
    </FilesMatch>
</Directory>
EOF
    a2enconf php-per-project.conf || true
}

phase4_install_tools() {
    print_info "FASE 4: Memasang Alat Bantu..."
    rm -f ${WEB_ROOT}/index.html
    if [ -f /vagrant/set_php_version.sh ]; then cp /vagrant/set_php_version.sh /usr/local/bin/set_php_version.sh; else cp ./set_php_version.sh /usr/local/bin/set_php_version.sh; fi
    chmod +x /usr/local/bin/set_php_version.sh
    echo "www-data ALL=(ALL) NOPASSWD: /usr/local/bin/set_php_version.sh" > /etc/sudoers.d/www-data-php-manager
    
    cd ${WEB_ROOT}
    wget -qO tinyfilemanager.php https://raw.githubusercontent.com/prasathmani/tinyfilemanager/master/tinyfilemanager.php
    mkdir -p file-manager; mv tinyfilemanager.php file-manager/index.php
    TFM_PASS_HASH=$(php -r "echo password_hash('$TFM_PASS', PASSWORD_DEFAULT);")
    sed -i "s#^// \$auth_users = array(#\$auth_users = array(#g" "${WEB_ROOT}/file-manager/index.php"
    sed -i "s#'admin' => '\$2y\$10\$KVMiF8xX25eQOXYN225m9uC4S3A9H2x2B.aQ.Y3oZ4a.aQ.Y3oZ4a'#'${TFM_USER}' => '${TFM_PASS_HASH}'#g" "${WEB_ROOT}/file-manager/index.php"
    sed -i "/'user'\s*=>/d" "${WEB_ROOT}/file-manager/index.php"; sed -i "s#\$root_path = \$_SERVER\['DOCUMENT_ROOT'\];#\$root_path = '${WEB_ROOT}';#g" "${WEB_ROOT}/file-manager/index.php"
    
    print_info "Membuat file dashboard utama 'index.php'..."
    cat <<'EOF' > ${WEB_ROOT}/index.php
<?php
// PHP Version Manager & Real-time Server Monitoring Dashboard
define('WEB_ROOT', '/var/www/html'); 
define('STATE_FILE', __DIR__ . '/config/project_versions.json');
define('EXCLUDED_ITEMS', ['.', '..', 'index.php', 'config', 'assets', 'phpMyAdmin', 'file-manager']);
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
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Server & Project Dashboard</title><script src="https://cdn.tailwindcss.com"></script></head><body class="bg-gray-100 text-gray-800 font-sans"><header class="bg-white shadow-md sticky top-0 z-10"><div class="container mx-auto px-6 py-4 flex justify-between items-center"><h1 class="text-2xl font-bold text-gray-800">Server Dashboard</h1><nav class="space-x-4"><a href="/file-manager/" target="_blank" class="text-indigo-600 hover:text-indigo-800 font-semibold">File Manager</a><a href="/phpMyAdmin" target="_blank" class="text-indigo-600 hover:text-indigo-800 font-semibold">phpMyAdmin</a></nav></div></header><main class="container mx-auto px-6 py-8"><section id="resource-stats" class="mb-10"><h2 class="text-2xl font-bold text-center text-gray-700 mb-6">Status Sumber Daya Server</h2><div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"><div class="bg-white rounded-lg shadow p-5 flex flex-col"><h3 class="text-lg font-semibold text-gray-800 mb-3 flex items-center"><svg class="h-6 w-6 text-indigo-500 mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M8.25 3v1.5M4.5 8.25H3m18 0h-1.5M4.5 12H3m18 0h-1.5m-15 3.75H3m18 0h-1.5M8.25 19.5V21M12 3v1.5m0 15V21m3.75-18v1.5m0 15V21m-9-1.5h10.5a2.25 2.25 0 002.25-2.25V8.25a2.25 2.25 0 00-2.25-2.25H6.75A2.25 2.25 0 004.5 8.25v7.5A2.25 2.25 0 006.75 18z" /></svg>CPU</h3><?php if ($cpu_info): ?><div class="w-full bg-gray-200 rounded-full h-6"><div id="cpu-bar" class="bg-indigo-500 h-6 text-xs font-medium text-indigo-100 text-center p-1 leading-none rounded-full" style="width: <?php echo $cpu_info['percent']; ?>%"><?php echo $cpu_info['percent']; ?>%</div></div><div class="flex justify-between text-sm text-gray-500 mt-2"><span id="cpu-text">Load: <?php echo $cpu_info['load']; ?></span><span>Cores: <?php echo $cpu_info['cores']; ?></span></div><?php else: ?><p class="text-red-500 font-semibold">Tidak Didukung.</p><?php endif; ?></div><div class="bg-white rounded-lg shadow p-5 flex flex-col"><h3 class="text-lg font-semibold text-gray-800 mb-3 flex items-center"><svg class="h-6 w-6 text-green-500 mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M8.25 7.5V6.108c0-1.135.845-2.098 1.976-2.192.373-.03.748-.03 1.125 0 1.131.094 1.976 1.057 1.976 2.192V7.5M8.25 7.5h7.5M8.25 7.5V9a.75.75 0 01-.75.75H5.25A.75.75 0 014.5 9V7.5m8.25 0V9a.75.75 0 00.75.75h2.25a.75.75 0 00.75-.75V7.5M12 10.5h.008v.008H12v-.008zM12 15h.008v.008H12v-.008zm0 2.25h.008v.008H12v-.008zM9.75 15h.008v.008H9.75v-.008zm0 2.25h.008v.008H9.75v-.008zM7.5 15h.008v.008H7.5v-.008zm0 2.25h.008v.008H7.5v-.008zm6.75-4.5h.008v.008h-.008v-.008zm0 2.25h.008v.008h-.008v-.008z" /></svg>RAM</h3><?php if ($memory_usage): ?><div class="w-full bg-gray-200 rounded-full h-6"><div id="ram-bar" class="bg-green-500 h-6 text-xs font-medium text-green-100 text-center p-1 leading-none rounded-full" style="width: <?php echo $memory_usage['percent']; ?>%"><?php echo $memory_usage['percent']; ?>%</div></div><div class="flex justify-between text-sm text-gray-500 mt-2"><span id="ram-text">Digunakan: <?php echo formatBytes($memory_usage['used']); ?></span><span>Total: <?php echo formatBytes($memory_usage['total']); ?></span></div><?php else: ?><p class="text-red-500 font-semibold">Tidak Didukung.</p><?php endif; ?></div><div class="bg-white rounded-lg shadow p-5 flex flex-col"><h3 class="text-lg font-semibold text-gray-800 mb-3 flex items-center"><svg class="h-6 w-6 text-sky-500 mr-2" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" /></svg>Penyimpanan</h3><?php if ($storage_usage): ?><div class="w-full bg-gray-200 rounded-full h-6"><div id="storage-bar" class="bg-sky-500 h-6 text-xs font-medium text-sky-100 text-center p-1 leading-none rounded-full" style="width: <?php echo $storage_usage['percent']; ?>%"><?php echo $storage_usage['percent']; ?>%</div></div><div class="flex justify-between text-sm text-gray-500 mt-2"><span id="storage-text">Digunakan: <?php echo formatBytes($storage_usage['used']); ?></span><span>Total: <?php echo formatBytes($storage_usage['total']); ?></span></div><?php else: ?><p class="text-red-500 font-semibold">Gagal membaca info disk.</p><?php endif; ?></div></div></section><hr class="my-10 border-gray-200"><section id="project-management"><?php if ($message): ?><div class="mb-6 p-4 rounded-md <?php echo $message_type === 'success' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'; ?>"><?php echo htmlspecialchars($message); ?></div><?php endif; ?><div class="bg-white rounded-lg shadow-lg"><div class="p-6 border-b border-gray-200"><h2 class="text-xl font-semibold">Manajemen Proyek</h2><p class="text-gray-600 mt-1">Atur versi PHP untuk setiap proyek.</p></div><div class="overflow-x-auto"><table class="min-w-full text-left"><thead class="bg-gray-50 border-b border-gray-200"><tr><th class="px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">Nama Proyek</th><th class="px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">Versi PHP</th><th class="px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">Aksi</th></tr></thead><tbody class="divide-y divide-gray-200">
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
    print_info "FASE 5: Finalisasi..."; mkdir -p ${WEB_ROOT}/config; touch ${WEB_ROOT}/config/project_versions.json
    chown -R www-data:www-data ${WEB_ROOT}; restart_service apache2
    apt-get autoremove -y
}
display_summary() {
    IP_ADDRESS=$(hostname -I | awk '{print $1}'); clear; print_success "INSTALASI SELESAI!"
    echo "======================================================================"; printf "\n"
    printf "  Dashboard: \e[1;36mhttp://%s/\e[0m\n\n" "${IP_ADDRESS}"
    printf "  Akses Alat Bantu:\n"; printf "+-----------------+------------------------------------------+\n"
    printf "| \e[1;32m%s\e[0m           | \e[1;36m%s\e[0m                                  |\n" "ALAT" "DETAIL"
    printf "+-----------------+------------------------------------------+\n"
    printf "| File Manager    | URL: http://%s/file-manager/      |\n" "${IP_ADDRESS}"
    printf "|                 | User: %-36s |\n" "${TFM_USER}"; printf "|                 | Pass: %-36s |\n" "${TFM_PASS}"
    printf "+-----------------+------------------------------------------+\n"
    printf "| phpMyAdmin      | URL: http://%s/phpMyAdmin       |\n" "${IP_ADDRESS}"
    printf "|                 | User: %-36s |\n" "${PMA_USER}"; printf "|                 | Pass: %-36s |\n" "${PMA_PASS}"
    printf "+-----------------+------------------------------------------+\n"
    printf "| DB Root         | User: root                               |\n"
    printf "|                 | Pass: %-36s |\n" "${MARIADB_ROOT_PASS}"
    printf "+-----------------+------------------------------------------+\n\n"
    print_warning "Catat semua kredensial ini dan simpan di tempat yang aman."
    echo "======================================================================"
}
main() {
    trap cleanup_on_error ERR; check_root
    if [ -f "$LOCK_FILE" ]; then
        print_warning "Ditemukan sisa instalasi yang mungkin gagal sebelumnya."
        read -p "Pilih tindakan: [1] Ulang dari Awal (bersihkan semua) atau [2] Keluar: " resume_choice < /dev/tty
        case $resume_choice in 1) silent_cleanup ;; *) echo "Instalasi dibatalkan."; exit 0 ;; esac
    fi
    touch "$LOCK_FILE"; get_setup_choices "$@"; phase1_setup_stack; phase2_install_multi_php; phase3_configure_apache
    phase4_install_tools; phase5_finalize; trap - ERR; rm -f "$LOCK_FILE"; display_summary
}
main "$@"