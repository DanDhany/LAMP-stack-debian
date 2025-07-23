Markdown

# Dashboard Server & Multi-PHP Manager

![PHP](https://img.shields.io/badge/PHP-7.4%20%7C%208.2-blue?style=for-the-badge&logo=php)
![Apache](https://img.shields.io/badge/Apache-2.4-red?style=for-the-badge&logo=apache)
![MariaDB](https://img.shields.io/badge/MariaDB-10.11-orange?style=for-the-badge&logo=mariadb)
![OS](https://img.shields.io/badge/OS-Debian%2012-purple?style=for-the-badge&logo=debian)

Sebuah skrip otomatis untuk mengubah server Debian 12 yang bersih menjadi sebuah lingkungan pengembangan web yang kuat dengan panel kontrol kustom berbasis web.

---

### ✨ Fitur Utama

* **Monitoring Server**: Pantau penggunaan CPU, RAM, dan Penyimpanan secara *real-time*.
* **Manajemen Multi-PHP**: Ganti versi PHP (7.4, 8.2) untuk setiap proyek secara independen melalui antarmuka web.
* **File Manager**: Antarmuka manajemen file lengkap (upload, edit, hapus, ekstrak) berbasis web.
* **Web SSH**: Akses terminal SSH server Anda langsung dari browser.
* **Database Manager**: Sudah termasuk phpMyAdmin untuk manajemen database MariaDB.
* **Instalasi Otomatis**: Cukup satu baris perintah untuk memasang semuanya.

---

### 🚀 Instalasi

Untuk melakukan instalasi, cukup jalankan salah satu dari perintah di bawah ini pada server **Debian 12 yang baru dan bersih**.

> **Peringatan:** Skrip ini akan menginstal dan mengkonfigurasi banyak paket. Menjalankannya pada server yang sudah ada dapat menimpa konfigurasi yang sudah ada.

#### Menggunakan `curl`

curl -fsSL [https://raw.githubusercontent.com/NAMA_USER_ANDA/NAMA_REPO_ANDA/main/install.sh](https://raw.githubusercontent.com/NAMA_USER_ANDA/NAMA_REPO_ANDA/main/install.sh) | sudo bash
Menggunakan wget
Bash

wget -qO- [https://raw.githubusercontent.com/NAMA_USER_ANDA/NAMA_REPO_ANDA/main/install.sh](https://raw.githubusercontent.com/NAMA_USER_ANDA/NAMA_REPO_ANDA/main/install.sh) | sudo bash
Setelah skrip berjalan, ia akan meminta beberapa input untuk mengatur password dan username. Setelah selesai, dashboard Anda akan siap digunakan.

🗑️ Uninstall
Untuk menghapus semua paket, konfigurasi, dan file yang telah diinstal oleh skrip ini, jalankan perintah di bawah.

Peringatan: Perintah ini akan menghapus Apache, MariaDB, PHP, dan semua alat bantu yang terpasang. Database Anda akan ikut terhapus. Lakukan backup jika ada data penting.

Bash

curl -fsSL [https://raw.githubusercontent.com/NAMA_USER_ANDA/NAMA_REPO_ANDA/main/uninstall.sh](https://raw.githubusercontent.com/NAMA_USER_ANDA/NAMA_REPO_ANDA/main/uninstall.sh) | sudo bash
📁 Struktur Proyek
install.sh: Skrip utama untuk instalasi.

uninstall.sh: Skrip untuk membersihkan instalasi.

README.md: File dokumentasi ini.

📜 Lisensi
Proyek ini dilisensikan di bawah Lisensi MIT.
