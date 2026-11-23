#!/usr/bin/env bash
# ==============================================================================
# Simulasi Beban CPU (Stress Test) - QA Proyek Sistem Operasi
# Skenario 1: deteksi threshold CPU & Auto-Renice.
#
# Pemakaian : ./tests/simulasi_beban_cpu.sh [DURASI_DETIK=30]
# Opsional  : WORKERS=4 LOAD=100 START_NICE=5 ./tests/simulasi_beban_cpu.sh 40
#   WORKERS    = jumlah worker (default: 1 per core)
#   LOAD       = % waktu tiap worker sibuk (default 100). 100 -> CPU total ~100%
#                (cukup untuk Critical >= 95%). Nilai lebih kecil = beban lebih
#                ringan, mis. LOAD=90 hanya sampai Warning.
#   START_NICE = nice awal worker (default 5). Worker berprioritas lebih rendah dari
#                aplikasi lain, jadi GUI/terminal VM tetap responsif walau CPU 100%.
#                Auto-renice agen tetap menaikkannya ke 10. START_NICE=0 = prioritas normal.
# Jalankan sebagai user biasa (BUKAN root) dan pastikan sensor_agent.sh aktif.
# ==============================================================================
set -u

DURATION=${1:-30}
WORKERS=${WORKERS:-$(nproc 2>/dev/null || echo 2)}   # 1 worker per core
LOAD=${LOAD:-100}
START_NICE=${START_NICE:-5}

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 2 ]; then
    echo "[TEST] Durasi harus bilangan bulat >= 2 detik." >&2; exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
    echo "[TEST] Jalankan sebagai user biasa: auto-action tidak menyentuh proses root." >&2; exit 1
fi
if ! [[ "$LOAD" =~ ^[0-9]+$ ]] || [ "$LOAD" -lt 1 ] || [ "$LOAD" -gt 100 ]; then
    echo "[TEST] LOAD harus 1-100." >&2; exit 1
fi
if ! [[ "$START_NICE" =~ ^[0-9]+$ ]] || [ "$START_NICE" -gt 9 ]; then
    echo "[TEST] START_NICE harus 0-9 (harus lebih kecil dari nilai renice agen, 10)." >&2; exit 1
fi
CHECK_AT=$(( DURATION < 12 ? DURATION - 1 : 12 ))    # beri waktu agen 1-2 siklus

# Worker: LOAD=100 -> loop penuh. LOAD<100 -> sibuk LOAD ms lalu tidur (100-LOAD) ms
# (butuh bash >= 5 untuk $EPOCHREALTIME; bila tidak ada, jatuh ke loop penuh).
worker() {
    local busy_us=$(( LOAD * 1000 )) idle end
    [ "$START_NICE" -gt 0 ] && renice -n "$START_NICE" -p "$BASHPID" >/dev/null 2>&1
    if [ "$LOAD" -ge 100 ] || [ -z "${EPOCHREALTIME:-}" ]; then
        while true; do :; done
    fi
    idle=$(printf '0.%03d' $(( 100 - LOAD )))
    while true; do
        end=$(( ${EPOCHREALTIME/./} + busy_us ))
        while [ "${EPOCHREALTIME/./}" -lt "$end" ]; do :; done
        sleep "$idle"
    done
}

PIDS=()
cleanup() {
    trap - INT TERM EXIT
    for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null; done
    wait 2>/dev/null
}
trap cleanup INT TERM EXIT

echo "[TEST] Memulai $WORKERS worker (beban ~${LOAD}%, nice awal ${START_NICE}) selama $DURATION detik..."
for ((i = 1; i <= WORKERS; i++)); do
    worker &
    PIDS+=($!)
    echo "[TEST] Worker $i -> PID ${PIDS[-1]}"
done
PIDLIST=$(IFS=,; echo "${PIDS[*]}")
sleep 0.5   # beri waktu worker memasang nice awal

echo "[TEST] Nice awal (NI harus ${START_NICE}):"
ps -o pid,ni,%cpu,comm -p "$PIDLIST"

sleep "$CHECK_AT"
echo "[TEST] Nice setelah ${CHECK_AT} detik (NI proses teratas harus 10):"
ps -o pid,ni,%cpu,comm -p "$PIDLIST"

sleep $(( DURATION - CHECK_AT ))
echo "[TEST] Selesai. Cek logs/alerts.log dan dashboard di Windows Host."
