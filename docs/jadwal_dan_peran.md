# Jadwal Kerja & Pembagian Peran Kelompok

## Susunan Tim & Peran Utama
1. **Kawthar (Ketua):** 
   - Koordinasi tim, manajemen jadwal kerja, integrasi repositori Git, dan komunikasi dengan dosen pengampu.
   - Penanggung jawab penyerahan dokumen.
2. **Aurel Ramdani (Pengembang Inti):** 
   - Perancangan arsitektur sensor Bash, implementasi mekanisme auto-action (renice/kill), sinkronisasi berkas.
   - Pembuatan dashboard visualisasi Python dan konfigurasi jaringan VM.
3. **Hafidz (Penguji / QA):** 
   - Perancangan skenario uji beban (stress testing), pengujian keamanan/hak akses.
   - Pencatatan bug, verifikasi hasil eksekusi agen, dan pembuat skrip simulasi beban.
4. **Faith (Dokumentator):** 
   - Penyusunan dokumen proposal, pembuatan berkas README.md, CHANGELOG.md, laporan akhir.
   - Penyusunan materi slide presentasi akhir.

---

## Timeline Pengerjaan (Pertemuan 12 – 15)

### Minggu 1 (Fase Kick-off & MVP) - Selesai ✅
- Penentuan topik studi kasus dan penyusunan proposal proyek lengkap.
- Inisialisasi repositori Git dan pembagian folder kerja (src, tests, docs, logs).
- Penyelesaian prototipe awal (MVP) `sensor_agent.sh` untuk pembacaan metrik dasar.
- Evaluasi jaringan dasar VM Ubuntu dan Windows.

### Minggu 2 (Fase Fitur Lanjutan & Visualisasi)
- Implementasi fitur threshold dan Auto-Action (renice/kill) pada skrip Bash.
- Penerapan sinkronisasi berkas (file locking dengan flock) dan izin chmod 640 pada file log.
- Pembuatan web dashboard berbasis Python (`dashboard_server.py`) dengan Chart.js.
- Konfigurasi jaringan Host-only dan UFW firewall.

### Minggu 3 (Fase Pengujian & Dokumentasi Tambahan)
- Pelaksanaan pengujian beban CPU (Stress Test) oleh QA.
- Pelaksanaan pengujian keamanan berkas (Concurrency & Permission Test).
- Pelaksanaan uji konektivitas lintas VM.
- Perbaikan bug berdasarkan hasil temuan uji.

### Minggu 4 (Fase Finalisasi & Presentasi)
- Penyusunan dan pemolesan Laporan Akhir Proyek.
- Pembuatan slide deck untuk presentasi kelompok.
- Latihan presentasi dan demonstrasi proyek.
