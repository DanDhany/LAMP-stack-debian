# ==============================================================================
# Dockerfile untuk Menguji Skrip Instalasi Dashboard di Debian 12
# ==============================================================================

# Gunakan base image Debian 12 yang sudah mendukung systemd.
FROM jrei/systemd-debian:12

# Set environment variable agar instalasi paket tidak interaktif.
ENV DEBIAN_FRONTEND=noninteractive

# Instal dependensi dasar yang dibutuhkan untuk menjalankan skrip installer.
# DIPERBARUI: Menambahkan 'dirmngr' untuk manajemen kunci PPA.
RUN apt-get update && apt-get install -y \
    nano \
    sudo \
    curl \
    wget \    
    software-properties-common \
    gnupg \
    dirmngr \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Buat user baru bernama 'tester' agar tidak selalu bekerja sebagai root.
RUN useradd -m -s /bin/bash tester && \
    usermod -aG sudo tester && \
    echo "tester ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Salin SEMUA skrip (.sh) dari folder lokal ke dalam image Docker.
COPY *.sh /home/tester/

# Atur kepemilikan dan izin eksekusi untuk SEMUA skrip yang disalin.
RUN chown tester:tester /home/tester/*.sh && \
    chmod +x /home/tester/*.sh

# Pindah ke direktori home milik user 'tester'.
USER tester
WORKDIR /home/tester

# Perintah default saat container dimulai.
CMD [ "/bin/bash" ]