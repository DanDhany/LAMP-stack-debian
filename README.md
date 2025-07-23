# 🚀 Dashboard Server & Multi-PHP Manager

Sebuah skrip otomatis untuk mengubah server **Debian 12** yang bersih menjadi lingkungan pengembangan web yang kuat dengan **panel kontrol kustom berbasis web**.

## ✨ Fitur Utama

- **Monitoring Server**  
  Pantau penggunaan CPU, RAM, dan Penyimpanan secara real-time.

- **Manajemen Multi-PHP**  
  Jalankan proyek dengan PHP versi berbeda (7.4, 8.2) secara independen melalui antarmuka web.

- **File Manager**  
  Kelola file langsung di browser: upload, edit, hapus, ekstrak, dan lainnya.

- **Web SSH**  
  Akses terminal server via web browser.

- **Database Manager**  
  Termasuk phpMyAdmin untuk manajemen database MariaDB.

- **Instalasi Otomatis**  
  Satu baris perintah cukup untuk memasang seluruh sistem.

---

## ⚙️ Instalasi

> 💡 **Catatan:** Skrip ini akan memasang dan mengonfigurasi banyak paket. Jangan gunakan di server dengan konfigurasi penting atau eksisting.

### Menggunakan `curl`

```bash
curl -fsSL https://raw.githubusercontent.com/DanDhany/LAMP-stack-debian/main/install.sh | sudo bash
```
Menggunakan wget
```bash
wget -qO- https://raw.githubusercontent.com/DanDhany/LAMP-stack-debian/main/install.sh | sudo bash
```
Setelah dijalankan, skrip akan meminta input seperti username dan password. Jika sudah selesai, dashboard siap digunakan.

### ⚙️ Pasca-Instalasi: Mengubah Konfigurasi

Setelah instalasi selesai, Anda dapat mengubah kredensial atau port yang telah diatur dengan menjalankan skrip editor.

1.  **Unduh skrip editor ke server Anda:**
    ```bash
    curl -fsSLO [https://raw.githubusercontent.com/NAMA_USER_ANDA/NAMA_REPO_ANDA/main/edit_config.sh](https://raw.githubusercontent.com/NAMA_USER_ANDA/NAMA_REPO_ANDA/main/edit_config.sh)
    chmod +x edit_config.sh
    ```
2.  **Jalankan dengan sudo:**
    ```bash
    sudo ./edit_config.sh
    ```
    Skrip akan menampilkan menu untuk mengubah password MariaDB, kredensial File Manager, dan lainnya.


🗑️ Uninstall
⚠️ Peringatan: Proses ini akan menghapus Apache, MariaDB, PHP, dan seluruh konfigurasi serta data terkait. Lakukan backup sebelum melanjutkan.

```bash
curl -fsSL https://raw.githubusercontent.com/DanDhany/LAMP-stack-debian/main/uninstall.sh | sudo bash
```
📜 Lisensi
Proyek ini dilisensikan di bawah MIT License.