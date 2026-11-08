#!/usr/bin/env bash
# ==============================================================================
# Skrip Pengujian Beban CPU (Stress Test) - QA Proyek Sistem Operasi
# Digunakan untuk menguji Skenario 1 (Deteksi Threshold & Auto-Renice)
# ==============================================================================

DURATION=${1:-20}
WORKERS=2

echo "[TEST] Memulai simulasi beban CPU dengan $WORKERS proses selama $DURATION detik..."
PIDS=()

for ((i=1; i<=WORKERS; i++)); do
    while true; do :; done &
    PIDS+=($!)
    echo "[TEST] Worker $i berjalan di background dengan PID: ${PIDS[-1]}"
done

echo "[TEST] Cek perubahan Nice Value (NI) proses setelah 5 detik:"
sleep 5
ps -o pid,ni,%cpu,comm -p "${PIDS[@]}"

sleep $((DURATION - 5))

echo "[TEST] Menghentikan seluruh proses simulasi..."
for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null
done
echo "[TEST] Selesai. Silakan periksa logs/alerts.log dan Web Dashboard di Windows Host."
