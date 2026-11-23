#!/usr/bin/env bash
# ==============================================================================
# Uji Konkurensi (Skenario 2, bagian flock): dua instans sensor_agent.sh menulis
# ke berkas log yang sama. Log dibuat di folder sementara (logs/ asli tidak tersentuh).
# Pemakaian: ./tests/uji_konkurensi.sh [DURASI_DETIK=15]
# ==============================================================================
set -u
DURATION=${1:-15}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRTG_LOG_DIR="$(mktemp -d)"
export PRTG_LOG_DIR PRTG_INTERVAL=1
CSV="$PRTG_LOG_DIR/sysmon.csv"
fail=0
check() { if [ "$2" = ok ]; then echo "  [PASS] $1"; else echo "  [FAIL] $1"; fail=1; fi; }

echo "[TEST] Menjalankan 2 instans agen selama $DURATION detik..."
OUT="$PRTG_LOG_DIR/agent.out"
"$ROOT/src/sensor_agent.sh" >"$OUT.1" 2>&1 & A1=$!
"$ROOT/src/sensor_agent.sh" >"$OUT.2" 2>&1 & A2=$!
sleep "$DURATION"
kill "$A1" "$A2" 2>/dev/null; wait 2>/dev/null

if [ ! -s "$CSV" ]; then
    echo "[TEST] GAGAL: agen tidak menghasilkan sysmon.csv. Keluaran agen:"
    grep -h -E "ERROR|Permission|denied" "$OUT".1 "$OUT".2 | sort -u | head -5
    rm -rf "$PRTG_LOG_DIR"; exit 1
fi
rows=$(( $(wc -l < "$CSV") - 1 ))
echo "[TEST] Baris data: $rows"
[ "$rows" -ge 2 ] && check "kedua instans menulis data" ok || check "kedua instans menulis data" no
[ "$(grep -c '^timestamp,' "$CSV")" -eq 1 ] && check "header hanya satu" ok || check "header hanya satu" no
bad=$(awk -F, 'NR>1 && NF!=10' "$CSV" | wc -l)
[ "$bad" -eq 0 ] && check "semua baris punya 10 kolom (tidak ada baris rusak/bertabrakan)" ok || check "ada $bad baris rusak" no
[ "$(stat -c %a "$CSV")" = 640 ] && check "izin berkas 640" ok || check "izin berkas 640 (sekarang $(stat -c %a "$CSV"))" no

rm -rf "$PRTG_LOG_DIR"
if [ "$fail" -eq 0 ]; then echo "[TEST] LULUS"; else echo "[TEST] GAGAL"; exit 1; fi
