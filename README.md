# PRTG-Lite OS Monitor (Kasus A - System Monitor)

Proyek Mata Kuliah **Sistem Operasi (TIK103)** — D4 Teknik Informatika, Politeknik Negeri Jakarta.
Solusi pemantauan sumber daya sistem operasi Linux secara *real-time* berbasis Bash & Python dengan fitur mitigasi proses otomatis (*Auto-Renice*), proteksi sinkronisasi berkas (*File Locking*), dan antarmuka Web Grafik yang diakses dari Host Windows melalui jaringan *Host-Only*.

## Susunan Anggota Kelompok
- **Kawthar Anugerah Kosasih** — Ketua Kelompok (Koordinasi & Manajemen Git)
- **Aurel Ramdani** — Pengembang Inti (Agen Sensor Bash & Dashboard Python)
- **Abdillah Hafidz Arrie Muchlisin** — Penguji / QA (Skrip Simulasi Beban & Skenario Uji)
- **Faith Kemal Arafi** — Dokumentator (Proposal, README, CHANGELOG, & Laporan)

## Struktur Repositori
```
src/sensor_agent.sh       agen sensor (CPU, RAM, Swap, Disk, Thread, proses teratas, auto-action)
src/dashboard_server.py   web server dashboard (0.0.0.0:8080) + API /api/metrics
src/prtg.conf             interval & ambang batas (dibaca agen DAN dashboard)
src/web/                  index.html, style.css, app.js (tampilan dashboard)
tests/                    simulasi_beban_cpu.sh, uji_konkurensi.sh, skenario_uji.md
docs/                     proposal & jadwal pengerjaan
logs/                     dibuat otomatis: sysmon.csv, alerts.log (tidak di-commit)
```

## Cara Menjalankan Proyek (Reproduksi)

### 1. Persiapan di VM Ubuntu (Server Sensor)
```bash
git clone https://github.com/relzzzx/PRTG-Lite-System-Monitor.git
cd PRTG-Lite-System-Monitor
chmod +x src/sensor_agent.sh tests/*.sh
sudo ufw allow 8080/tcp
```
> Jalankan semua perintah berikut sebagai **user biasa**, bukan root. Auto-action hanya
> menertibkan proses user (UID >= 1000), tidak pernah proses root/sistem.

### 2. Menjalankan Agen Sensor & Web Server di Ubuntu
Buka terminal di VM Ubuntu:
```bash
# Jalankan agen sensor di background
./src/sensor_agent.sh &

# Jalankan web server dashboard di port 8080
python3 src/dashboard_server.py
```
Server akan mencetak URL yang bisa dibuka dari Windows untuk tiap IP VM. Hentikan agen dengan `kill %1`.

### 3. Mengakses Dashboard dari Windows (Host)
1. Cek IP Host-Only VM Ubuntu dengan perintah `ip addr show` (misal: `192.168.56.101`).
2. Buka browser di Windows Host (Chrome/Edge) dan akses:
   `http://192.168.56.101:8080`

> Browser Windows memerlukan internet untuk memuat library Chart.js dari CDN (VM tidak perlu).

### 4. Menjalankan Pengujian
Buka terminal baru di Ubuntu (agen dan dashboard tetap berjalan):
```bash
# Skenario 1: beban CPU -> Auto-Renice (grafik melonjak, status berubah)
./tests/simulasi_beban_cpu.sh 20

# Skenario 2: dua agen menulis log bersamaan (uji flock + izin berkas 640)
./tests/uji_konkurensi.sh
```
Skrip simulasi memakai nice awal 5 agar VM tidak freeze; nilai nice proses teratas akan naik ke 10 oleh agen.
Opsi: `WORKERS=<n> LOAD=<1-100> START_NICE=<0-9> ./tests/simulasi_beban_cpu.sh 30`.
Langkah dan kriteria lulus lengkap ada di `tests/skenario_uji.md`.

## Konfigurasi (`src/prtg.conf`)
Dibaca oleh agen dan dashboard, jadi ambang batas keduanya selalu sama. Restart agen & server setelah mengubahnya.

| Kunci | Default | Keterangan |
|---|---|---|
| `INTERVAL` | 5 | detik antar pembacaan sensor |
| `CPU_WARN` / `CPU_CRIT` | 80 / 95 | ambang CPU (%) |
| `MEM_*`, `SWAP_*`, `DISK_*` | 80/90, 50/80, 80/90 | ambang RAM, Swap, Disk (%) |
| `RENICE_VALUE` | 10 | nilai nice saat CPU >= Warning |
| `MIN_ACTION_UID` | 1000 | hanya proses UID >= nilai ini yang ditertibkan |
| `AUTO_KILL` | 0 | `1` = kirim SIGTERM saat CPU >= Critical pada proses yang sudah di-renice |
| `MAX_LOG_LINES` | 5000 | rotasi log: simpan N baris terbaru |

Port dashboard bisa diganti: `PRTG_PORT=9090 python3 src/dashboard_server.py` (jangan lupa `ufw allow`).

## Format Log
`logs/sysmon.csv`:
`timestamp,cpu_usage,mem_usage,swap_usage,disk_usage,total_threads,top_pid,top_proc_name,top_proc_cpu,status`

Nilai `status`: `OK`, `WARNING_<SENSOR>`, `CRITICAL_<SENSOR>`, `WARNING_RENICED`, `CRITICAL_RENICED`, `CRITICAL_KILLED`.
`logs/alerts.log` mencatat peringatan (INFO / WARNING / CRITICAL) hanya saat status berubah.

## Pemecahan Masalah
- **Agen berhenti dengan error `/tmp/sysmon.lock`:** berkas kunci dibuat user lain dengan izin ketat. Hapus sekali: `sudo rm /tmp/sysmon.lock`.
- **`bad interpreter` / `^M` saat menjalankan `.sh`:** berkas berakhir baris CRLF. `.gitattributes` sudah memaksa LF; jalankan `git pull` ulang atau `dos2unix`.
- **Grafik kosong di browser:** pastikan browser Windows punya internet (Chart.js CDN) dan agen sensor sedang berjalan.