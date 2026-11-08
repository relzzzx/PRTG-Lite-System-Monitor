# PRTG-Lite OS Monitor (Kasus A - System Monitor)

Proyek Mata Kuliah **Sistem Operasi (TIK103)** — D4 Teknik Informatika, Politeknik Negeri Jakarta.
Solusi pemantauan sumber daya sistem operasi Linux secara *real-time* berbasis Bash & Python dengan fitur mitigasi proses otomatis (*Auto-Renice*), proteksi sinkronisasi berkas (*File Locking*), dan antarmuka Web Grafik yang diakses dari Host Windows melalui jaringan *Host-Only*.

## Susunan Anggota Kelompok
- **Kawthar** — Ketua Kelompok (Koordinasi & Manajemen Git)
- **Aurel Ramdani** — Pengembang Inti (Agen Sensor Bash & Dashboard Python)
- **Hafidz** — Penguji / QA (Skrip Simulasi Beban & Skenario Uji)
- **Faith** — Dokumentator (Proposal, README, CHANGELOG, & Laporan)

## Cara Menjalankan Proyek (Reproduksi)

### 1. Persiapan di VM Ubuntu (Server Sensor)
```bash
git clone https://github.com/relzzzx/PRTG-Lite-System-Monitor.git
cd PRTG-Lite-System-Monitor
chmod +x src/sensor_agent.sh tests/simulasi_beban_cpu.sh
sudo ufw allow 8080/tcp
```

### 2. Menjalankan Agen Sensor & Web Server di Ubuntu
Buka terminal di VM Ubuntu:
```bash
# Jalankan agen sensor di background
./src/sensor_agent.sh &

# Jalankan web server dashboard di port 8080
python3 src/dashboard_server.py
```

### 3. Mengakses Dashboard dari Windows (Host)
1. Cek IP Host-Only VM Ubuntu dengan perintah `ip addr show` (misal: `192.168.56.101`).
2. Buka browser di Windows Host (Chrome/Edge) dan akses:
   `http://192.168.56.101:8080`

### 4. Menjalankan Pengujian Beban (Stress Test)
Untuk melihat grafik melonjak dan fitur *Auto-Renice* bekerja secara langsung, buka terminal baru di Ubuntu dan jalankan:
```bash
./tests/simulasi_beban_cpu.sh 20
```
