# Dokumen Skenario Pengujian (QA)

Mengacu pada Bab 7 proposal. Ambang batas & interval ada di `src/prtg.conf`
(default: interval 5 dtk, CPU Warning 80% / Critical 95%).
Jalankan semua pengujian sebagai **user biasa** (bukan root).

## Skenario 1: Uji Beban CPU & Mitigasi Otomatis (Auto-Renice)
- **Tujuan:** `sensor_agent.sh` mendeteksi CPU > 80% dan menurunkan prioritas proses (`renice`, nice = 10).
- **Langkah Uji:**
  1. Terminal 1: `./src/sensor_agent.sh`
  2. Terminal 2 (pilih salah satu):
     - Otomatis: `./tests/simulasi_beban_cpu.sh 30`
     - Manual (sesuai proposal): `while true; do :; done &` lalu `ps -o pid,ni,%cpu,comm -p <PID>`
  3. Amati kolom `NI` berubah dari nice awal (skrip otomatis: `5`; loop manual: `0`) menjadi `10`, periksa `logs/alerts.log` dan kartu CPU di dashboard.
- **Catatan:** skrip otomatis memakai `LOAD=100` (CPU ~100% -> `CRITICAL_RENICED`) dan `START_NICE=5` agar VM tidak freeze. `LOAD=85` menghasilkan `WARNING_RENICED`.
- **Kriteria Lulus:** status `WARNING_RENICED` / `CRITICAL_RENICED` pada `sysmon.csv`, `NI` = 10, dan `alerts.log` mencatat **satu** peringatan untuk proses tersebut (tidak berulang tiap siklus).
- **Setelah selesai:** hentikan loop manual dengan `kill <PID>` (atau `kill %1`).

## Skenario 2: Uji Konkurensi (`flock`) & Hak Akses Berkas (`chmod 640`)
- **Tujuan:** tidak ada *race condition* saat penulisan log dan berkas log terlindungi.
- **Langkah Uji:**
  1. Konkurensi otomatis: `./tests/uji_konkurensi.sh` (menjalankan 2 instans agen; semua cek harus `[PASS]`).
     Manual: jalankan `./src/sensor_agent.sh` di dua terminal bersamaan, lalu
     `awk -F, 'NR>1 && NF!=10' logs/sysmon.csv` (tidak boleh ada keluaran).
  2. Cek izin: `ls -l logs/sysmon.csv` (harus `-rw-r-----`).
  3. Buat user uji: `sudo adduser mhsprak`, lalu
     `su - mhsprak -c "cat /path/ke/logs/sysmon.csv"` dan `su - mhsprak -c "rm /path/ke/logs/sysmon.csv"`.
- **Kriteria Lulus:** tidak ada baris rusak/bertabrakan; akun `mhsprak` mendapat `Permission denied`.

## Skenario 3: Uji Konektivitas & Visualisasi Lintas VM (Host-Only)
- **Tujuan:** dashboard dapat diakses dari browser Windows melalui jaringan Host-Only.
- **Langkah Uji:**
  1. Ubuntu: `sudo ufw allow 8080/tcp`, lalu `python3 src/dashboard_server.py`
     (server mencetak URL `http://<IP>:8080` untuk tiap alamat IPv4 VM).
  2. Ubuntu: `ip addr` dan `ss -tulpn | grep 8080` (harus `LISTEN` pada `0.0.0.0:8080`).
  3. Windows (Command Prompt): `ping <IP_Ubuntu>`, buka `http://<IP_Ubuntu>:8080`,
     lalu `netstat -an | findstr 8080` (harus ada koneksi `ESTABLISHED`).
  4. Jalankan Skenario 1 dan amati grafik serta kartu sensor berubah di browser.
- **Kriteria Lulus:** dashboard tampil dan grafik bergerak real-time; koneksi tercatat di `ss -tulpn` (Ubuntu) dan `netstat -an` (Windows).
- **Catatan:** browser Windows butuh internet untuk memuat Chart.js dari CDN (VM tidak perlu).