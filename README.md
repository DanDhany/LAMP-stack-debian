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

🗑️ Uninstall
⚠️ Peringatan: Proses ini akan menghapus Apache, MariaDB, PHP, dan seluruh konfigurasi serta data terkait. Lakukan backup sebelum melanjutkan.

```bash
curl -fsSL https://raw.githubusercontent.com/DanDhany/LAMP-stack-debian/main/uninstall.sh | sudo bash
```
📜 Lisensi
Proyek ini dilisensikan di bawah MIT License.