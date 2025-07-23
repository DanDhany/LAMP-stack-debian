# ==============================================================================
# Dockerfile untuk Menguji Skrip Instalasi Dashboard di Debian 12 (Versi Sederhana)
# ==============================================================================

# Gunakan base image Debian 12 yang sudah mendukung systemd.
FROM jrei/systemd-debian:12

# Set environment variable agar instalasi paket tidak interaktif.
ENV DEBIAN_FRONTEND=noninteractive

# Instal dependensi dasar yang dibutuhkan untuk menjalankan skrip installer.
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

# DIHAPUS: Perintah COPY dan CHMOD/CHOWN skrip dihapus dari sini
# karena sekarang ditangani oleh bind mount di docker-compose.yml

# Pindah ke direktori home milik user 'tester'.
USER tester
WORKDIR /home/tester

# Perintah default saat container dimulai.
CMD [ "/bin/bash" ]