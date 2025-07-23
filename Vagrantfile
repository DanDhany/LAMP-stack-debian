# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Menggunakan image resmi Debian 12 (Bookworm) 64-bit.
  config.vm.box = "debian/bookworm64"

  # Meneruskan port 80 dari dalam VM ke port 8088 di komputer Windows Anda.
  config.vm.network "forwarded_port", guest: 80, host: 8088

  # Konfigurasi untuk provider VirtualBox.
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
  end

  # ====================================================================
  # PROVISIONING OTOMATIS (VERSI BARU)
  # ====================================================================
  # Menjalankan skrip pembungkus dan memberikan semua jawaban
  # yang dibutuhkan oleh install.sh sebagai argumen.

  config.vm.provision "shell", path: "vagrant_provision.sh", args: [
      # Argumen ke-1: Mode Instalasi ('1' untuk otomatis)
      "1",
      # Argumen ke-2: Gunakan Systemd ('yes', karena VM Vagrant adalah OS penuh)
      "yes",
      # Argumen ke-3: Pilihan Versi PHP (pisahkan koma, tanpa spasi. misal: "7.4,8.2")
      "7.4,8.2",
      # Argumen ke-4: Password Root MariaDB
      "vagrantroot",
      # Argumen ke-5: User phpMyAdmin
      "pma_user",
      # Argumen ke-6: Password User phpMyAdmin
      "pma_password",
      # Argumen ke-7: User File Manager
      "fm_admin",
      # Argumen ke-8: Password File Manager
      "fm_password"
  ]
end