# Changelog Proyek Sistem Operasi

## [v0.2.0] - 2026-11-23 (Audit MVP, Upgrade UI/UX & Refactoring)
### Added
- `src/prtg.conf`: konfigurasi bersama agen & dashboard (interval 5 dtk, ambang Warning/Critical CPU/RAM/Swap/Disk, renice, auto-kill, rotasi log).
- Level **Critical** dan opsi `AUTO_KILL` (SIGTERM, default nonaktif) sesuai proposal; rotasi log `MAX_LOG_LINES`.
- Dashboard dipecah menjadi `src/web/{index.html,style.css,app.js}` dengan tema gelap mengacu ke referensi DCIM (sidebar, kartu sensor Up/Warning/Critical, area chart CPU & RAM/Swap, donut status, recent alerts, top process).
- `tests/uji_konkurensi.sh` (Skenario 2: dua instans agen + validasi log); `.gitignore` dan `.gitattributes` (LF untuk `.sh`).
### Changed
- `src/sensor_agent.sh` ditulis ulang: RAM via `MemAvailable`, CPU via kolom `id` vmstat, header CSV sesuai Tabel 5 proposal, alert hanya saat status berubah, `trap` Ctrl+C, validasi konfigurasi.
- Ambang CPU 75% -> 80% dan interval 3 dtk -> 5 dtk (sesuai proposal).
- `src/dashboard_server.py`: `ThreadingHTTPServer` (tetap bind `0.0.0.0:8080`), pembacaan log dengan `flock` bersama, parser CSV tahan baris rusak, 404 untuk path tak dikenal.
- `tests/simulasi_beban_cpu.sh`: worker = jumlah core, `LOAD=100` dan `START_NICE=5` agar VM tidak freeze, `trap` pembersih proses, validasi durasi.
- `tests/skenario_uji.md` dan `README.md` diselaraskan dengan proposal dan kode terbaru.
### Fixed
- Auto-renice tidak pernah jalan untuk loop `while true; do :; done &` (nama proses `bash` dikecualikan); kini filter berbasis UID, daftar proses terlindungi, dan induk agen.
- Status `RENICED` dicatat walau `renice` gagal; alert berulang tiap siklus.
- Jumlah thread terhitung termasuk baris header `ps`.
- Dashboard tidak lagi crash pada baris CSV terpotong dan tidak membaca seluruh berkas tiap request.
- Agen gagal menulis log bila `/tmp/sysmon.lock` dibuat user lain (mis. agen root vs tes ubuntu): berkas kunci kini dibuat izin 666 dan hanya dibuka read-only, dengan pesan error jelas bila tetap gagal.

## [v0.1.0] - 2026-11-08 (Target Pertemuan 12 - MVP & Proposal)
### Added
- Penyusunan dokumen Proposal Proyek dan Tabel Pemetaan Konsep SO (`docs/Proposal_PRTG_Lite_OS_Monitor.docx`).
- Implementasi MVP `src/sensor_agent.sh` untuk pembacaan metrik CPU, RAM, Swap, Disk, dan Thread secara berkala.
- Penambahan mekanisme sinkronisasi berkas (`flock`), pengaturan izin `chmod 640`, dan mitigasi otomatis `renice +10`.
- Pembuatan antarmuka visualisasi grafik `src/dashboard_server.py` menggunakan Python HTTP Server.
- Pembuatan skrip pengujian beban CPU `tests/simulasi_beban_cpu.sh` dan dokumentasi skenario uji.
- Menambahkan dokumen jadwal kerja dan peran kelompok (`docs/jadwal_dan_peran.md`).