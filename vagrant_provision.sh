#!/bin/bash

# ==============================================================================
#   Skrip Pembungkus untuk Menjalankan install.sh di Vagrant
# ==============================================================================
#   Skrip ini mengambil argumen dari Vagrantfile dan meneruskannya
#   ke skrip install.sh utama, memungkinkannya berjalan non-interaktif.
# ==============================================================================

# Pindah ke direktori /vagrant di mana semua file proyek berada
cd /vagrant

# Jalankan skrip instalasi utama, meneruskan semua argumen ($@)
# yang diterima dari Vagrantfile.
sudo ./install.sh "$@"