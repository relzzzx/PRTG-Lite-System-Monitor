# Dokumen Skenario Pengujian (QA)

## Skenario 1: Uji Beban CPU & Mitigasi Otomatis (Auto-Renice)
- **Tujuan:** Memastikan `sensor_agent.sh` mampu mendeteksi lonjakan CPU > 75% dan menurunkan prioritas proses (`renice +10`).
- **Langkah Uji:**
  1. Jalankan `./src/sensor_agent.sh` di terminal 1.
  2. Jalankan `./tests/simulasi_beban_cpu.sh 20` di terminal 2.
  3. Amati perubahan kolom `NI` (Nice value) dari `0` menjadi `10` dan periksa `logs/alerts.log`.
- **Kriteria Lulus:** Status berubah menjadi `WARN_RENICED` dan nilai `NI` berubah menjadi `10`.

## Skenario 2: Uji Sinkronisasi Log (`flock`) & Hak Akses Berkas (`chmod 640`)
- **Tujuan:** Memastikan tidak terjadi *race condition* saat penulisan log dan menguji keamanan berkas.
- **Langkah Uji:**
  1. Cek izin berkas dengan `ls -l logs/sysmon.csv` (harus `-rw-r-----`).
  2. Buat user pengujian non-admin (`sudo adduser mhsprak`), lalu coba baca/hapus file log menggunakan akun tersebut (`su - mhsprak -c "rm /path/to/logs/sysmon.csv"`).
- **Kriteria Lulus:** Akses ditolak (*Permission denied*) bagi pengguna `others`.

## Skenario 3: Uji Jaringan Host-Only (VM Ubuntu ke Host Windows)
- **Tujuan:** Memastikan Web Dashboard dapat diakses dari browser Windows Host melalui jaringan Host-Only.
- **Langkah Uji:**
  1. Aktifkan firewall `sudo ufw allow 8080/tcp` dan jalankan `python3 src/dashboard_server.py`.
  2. Dari Command Prompt Windows Host, jalankan `ping <IP_Ubuntu>` dan `netstat -an | findstr 8080`.
  3. Buka `http://<IP_Ubuntu>:8080` di browser Windows Host.
- **Kriteria Lulus:** Grafik *real-time* tampil dan merespons perubahan beban dari Skenario 1.
