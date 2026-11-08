# Changelog Proyek Sistem Operasi

## [v0.1.0] - 2026-11-08 (Target Pertemuan 12 - MVP & Proposal)
### Added
- Penyusunan dokumen Proposal Proyek dan Tabel Pemetaan Konsep SO (`docs/Proposal_PRTG_Lite_OS_Monitor.docx`).
- Implementasi MVP `src/sensor_agent.sh` untuk pembacaan metrik CPU, RAM, Swap, Disk, dan Thread secara berkala.
- Penambahan mekanisme sinkronisasi berkas (`flock`), pengaturan izin `chmod 640`, dan mitigasi otomatis `renice +10`.
- Pembuatan antarmuka visualisasi grafik `src/dashboard_server.py` menggunakan Python HTTP Server.
- Pembuatan skrip pengujian beban CPU `tests/simulasi_beban_cpu.sh` dan dokumentasi skenario uji.
- Menambahkan dokumen jadwal kerja dan peran kelompok (`docs/jadwal_dan_peran.md`).
