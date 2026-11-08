#!/usr/bin/env bash
# ==============================================================================
# PRTG-Lite OS Sensor Agent (Kasus A - System Monitor)
# Tugas Pengembang Inti: Pengambilan Metrik, Sinkronisasi (flock), & Auto-Renice
# ==============================================================================

INTERVAL=3
CPU_WARN_LIMIT=75
MEM_WARN_LIMIT=80

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
CSV_LOG="$LOG_DIR/sysmon.csv"
ALERT_LOG="$LOG_DIR/alerts.log"
LOCK_FILE="/tmp/sysmon.lock"

mkdir -p "$LOG_DIR"

# Inisialisasi header CSV dan atur izin berkas (Praktikum 8: chmod 640)
if [ ! -f "$CSV_LOG" ]; then
    echo "timestamp,cpu,mem,swap,disk,threads,top_pid,top_proc,top_cpu,status" > "$CSV_LOG"
    chmod 640 "$CSV_LOG"
fi
touch "$ALERT_LOG" && chmod 640 "$ALERT_LOG"

echo "[INFO] PRTG-Lite Sensor Agent berjalan... (Tekan Ctrl+C untuk berhenti)"
echo "[INFO] Log disimpan di: $CSV_LOG (Permission: 640)"

while true; do
    TS=$(date '+%Y-%m-%d %H:%M:%S')

    # 1. Manajemen CPU & Memori (Praktikum 6: vmstat & free)
    CPU=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
    MEM=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2)*100}')

    # 2. Memori Virtual / Swap (Praktikum 7: free Swap)
    SWAP=$(free | awk '/Swap:/ {if ($2==0) print 0; else printf "%.0f", ($3/$2)*100}')

    # 3. Manajemen Berkas & I/O Disk (Praktikum 8 & 9: df)
    DISK=$(df / | tail -1 | awk '{gsub(/%/,"",$5); print $5}')

    # 4. Thread & Multithreading (Praktikum 4: ps -eLf)
    THREADS=$(ps -eLf | wc -l)

    # 5. Manajemen Proses: Cari proses pengguna dengan CPU tertinggi (Praktikum 3)
    TOP_INFO=$(ps -u "$USER" -o pid,%cpu,comm --sort=-%cpu | awk 'NR==2 {print $1","$3","$2}')
    TOP_PID=$(echo "$TOP_INFO" | cut -d',' -f1)
    TOP_PROC=$(echo "$TOP_INFO" | cut -d',' -f2)
    TOP_CPU=$(echo "$TOP_INFO" | cut -d',' -f3)

    STATUS="OK"

    # 6. Evaluasi Ambang Batas & Auto-Action (Praktikum 3: renice)
    if [ "$CPU" -ge "$CPU_WARN_LIMIT" ]; then
        STATUS="WARNING_CPU"
        if [ -n "$TOP_PID" ] && [ "$TOP_PROC" != "ps" ] && [ "$TOP_PROC" != "bash" ]; then
            renice -n 10 -p "$TOP_PID" >/dev/null 2>&1
            STATUS="WARN_RENICED(PID:$TOP_PID)"
            echo "[$TS] CRITICAL SENSOR: CPU=${CPU}%! Proses '$TOP_PROC' (PID $TOP_PID) diturunkan prioritasnya (renice +10)." >> "$ALERT_LOG"
        fi
    elif [ "$MEM" -ge "$MEM_WARN_LIMIT" ]; then
        STATUS="WARNING_MEM"
        echo "[$TS] WARNING SENSOR: Memori tinggi (${MEM}%)!" >> "$ALERT_LOG"
    fi

    # 7. Sinkronisasi Proses: Tulis ke berkas menggunakan flock (Praktikum 5)
    (
        flock -x 200
        echo "$TS,$CPU,$MEM,$SWAP,$DISK,$THREADS,$TOP_PID,$TOP_PROC,$TOP_CPU,$STATUS" >> "$CSV_LOG"
    ) 200>"$LOCK_FILE"

    echo "[$TS] CPU:${CPU}% | MEM:${MEM}% | SWAP:${SWAP}% | DISK:${DISK}% | Threads:${THREADS} | Top:${TOP_PROC}(${TOP_CPU}%) | Status:${STATUS}"
    sleep "$INTERVAL"
done