#!/usr/bin/env bash
# ==============================================================================
# PRTG-Lite OS Sensor Agent (Kasus A - System Monitor)
#
# Membaca metrik OS tiap INTERVAL detik -> logs/sysmon.csv (flock + chmod 640),
# lalu mengevaluasi ambang batas dan menjalankan Auto-Action (renice / kill).
#
# Pemetaan praktikum:
#   P2/P8 CLI, chmod 640, chown   P3 ps, renice, kill   P4 ps -eLf (thread)
#   P5 flock                      P6/P7 /proc/meminfo (RAM, swap)
#   P9 df, lsblk                  P10 dashboard via jaringan Host-Only
#
# Konfigurasi: src/prtg.conf (dibagi dengan dashboard_server.py)
# ==============================================================================
set -u
umask 027
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# ---- Default (ditimpa oleh prtg.conf bila ada) --------------------------------
INTERVAL=5
CPU_WARN=80;  CPU_CRIT=95
MEM_WARN=80;  MEM_CRIT=90
SWAP_WARN=50; SWAP_CRIT=80
DISK_WARN=80; DISK_CRIT=90
RENICE_VALUE=10
MIN_ACTION_CPU=20
MIN_ACTION_UID=1000
AUTO_KILL=0
MAX_LOG_LINES=5000
LOCK_FILE=/tmp/sysmon.lock
LOG_GROUP=

CONF_FILE="${PRTG_CONF:-$SCRIPT_DIR/prtg.conf}"
# tr -d '\r' -> tetap terbaca walau berkas konfigurasi tersimpan CRLF (Windows)
# shellcheck source=/dev/null
[ -r "$CONF_FILE" ] && . <(tr -d '\r' < "$CONF_FILE")

# Override untuk pengujian (mis. tests/uji_konkurensi.sh)
INTERVAL="${PRTG_INTERVAL:-$INTERVAL}"
LOG_DIR="${PRTG_LOG_DIR:-$BASE_DIR/logs}"
CSV_LOG="$LOG_DIR/sysmon.csv"
ALERT_LOG="$LOG_DIR/alerts.log"

# Header sesuai Tabel 5 proposal
CSV_HEADER="timestamp,cpu_usage,mem_usage,swap_usage,disk_usage,total_threads,top_pid,top_proc_name,top_proc_cpu,status"

# Proses yang tidak pernah disentuh auto-action (proposal: Risiko 1)
PROTECTED_RE='^(systemd.*|sshd.*|gnome-shell.*|Xorg.*|dbus.*|login|init|NetworkManager.*|sensor_agent.sh)$'
# Proses bantu milik agen sendiri (tidak dihitung sebagai "proses teratas")
HELPER_RE='^(ps|vmstat|awk|tail|head|sleep|flock|renice|df|wc|cat|tr|date|mktemp)$'

declare -A RENICED=()   # PID -> ok|fail (cegah renice & alert berulang)
PREV_STATUS="OK"
ACTION_STATUS=""

# ---- Utilitas ------------------------------------------------------------------
log_info()  { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

require_cmds() {
    local missing=() c
    for c in vmstat ps awk flock renice df date; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log_error "Perintah tidak ditemukan: ${missing[*]}"
        exit 1
    fi
}

validate_config() {
    local v
    for v in INTERVAL CPU_WARN CPU_CRIT MEM_WARN MEM_CRIT SWAP_WARN SWAP_CRIT \
             DISK_WARN DISK_CRIT RENICE_VALUE MIN_ACTION_CPU MIN_ACTION_UID \
             AUTO_KILL MAX_LOG_LINES; do
        if ! [[ "${!v}" =~ ^[0-9]+$ ]]; then
            log_error "Nilai $v di $CONF_FILE harus bilangan bulat (sekarang: '${!v}')"
            exit 1
        fi
    done
    [ "$INTERVAL" -ge 1 ] || { log_error "INTERVAL minimal 1 detik"; exit 1; }
}

# Berkas kunci dibuat sekali dengan izin 666 lalu hanya DIBUKA (read-only, tanpa O_CREAT).
# Dengan begitu agen/dashboard milik user berbeda (mis. root vs ubuntu) tetap bisa berbagi
# kunci, dan tidak terhalang fs.protected_regular milik Ubuntu pada /tmp.
ensure_lock_file() {
    [ -e "$LOCK_FILE" ] || ( umask 000; : > "$LOCK_FILE" ) 2>/dev/null
    if ! [ -r "$LOCK_FILE" ]; then
        log_error "Berkas kunci $LOCK_FILE tidak bisa dibuka oleh user '$(id -un)'."
        log_error "Biasanya dibuat user lain dengan izin ketat. Hapus sekali: sudo rm $LOCK_FILE"
        exit 1
    fi
}

# Tulis baris ke berkas log di bawah kunci eksklusif (Praktikum 5: flock)
locked_append() {   # $1=berkas $2=baris
    ( flock -x -w 5 200 || exit 1; printf '%s\n' "$2" >> "$1" ) 200<"$LOCK_FILE"
}

write_alert() {     # $1=LEVEL $2=pesan
    locked_append "$ALERT_LOG" "[$TS] $1: $2"
}

init_logs() {
    mkdir -p "$LOG_DIR" && chmod 750 "$LOG_DIR" 2>/dev/null
    (
        flock -x -w 5 200 || exit 1
        [ -s "$CSV_LOG" ] || printf '%s\n' "$CSV_HEADER" > "$CSV_LOG"   # header sekali saja
        touch "$ALERT_LOG"
        chmod 640 "$CSV_LOG" "$ALERT_LOG"                               # Praktikum 8
        if [ -n "$LOG_GROUP" ]; then
            chgrp "$LOG_GROUP" "$LOG_DIR" "$CSV_LOG" "$ALERT_LOG" 2>/dev/null \
                || log_info "chgrp ke '$LOG_GROUP' dilewati (bukan anggota grup?)"
        fi
    ) 200<"$LOCK_FILE"
}

# Rotasi: pertahankan N baris terbaru (mitigasi Risiko 2). Inode & izin tetap.
trim_file() {       # $1=berkas $2=maks baris $3=1 bila ada header
    local f=$1 max=$2 hdr=$3 tmp keep
    [ -f "$f" ] || return 0
    [ "$(wc -l < "$f")" -gt "$max" ] || return 0
    keep=$(( max * 8 / 10 ))
    tmp=$(mktemp "$f.XXXXXX") || return 0
    { [ "$hdr" = 1 ] && head -n 1 "$f"; tail -n "$keep" "$f"; } > "$tmp"
    cat "$tmp" > "$f"
    rm -f "$tmp"
}

maintain_logs() {
    (
        flock -x -w 5 200 || exit 1
        trim_file "$CSV_LOG" "$MAX_LOG_LINES" 1
        trim_file "$ALERT_LOG" "$MAX_LOG_LINES" 0
    ) 200<"$LOCK_FILE"
}

# ---- Pembacaan sensor ----------------------------------------------------------
# CPU (Praktikum 6): kolom 'id' dicari lewat header vmstat, bukan angka tetap.
read_cpu() {
    vmstat 1 2 2>/dev/null | awk '
        NR==2 { for (i=1;i<=NF;i++) if ($i=="id") c=i }
        NR==4 && c { v=100-$c; if (v<0) v=0; if (v>100) v=100; printf "%d", v+0.5 }'
}

# RAM & Swap (Praktikum 6/7): memakai MemAvailable (sudah memperhitungkan buffer/cache).
read_mem_swap() {
    awk '
        /^MemTotal:/{mt=$2} /^MemAvailable:/{ma=$2} /^MemFree:/{mf=$2}
        /^Buffers:/{bu=$2} /^Cached:/{ca=$2} /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
        END {
            if (ma=="") ma=mf+bu+ca
            m=(mt>0)?(mt-ma)*100/mt:0
            s=(st>0)?(st-sf)*100/st:0
            printf "%d %d", m+0.5, s+0.5
        }' /proc/meminfo
}

read_disk()    { df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}'; }
read_threads() { ps -eLf 2>/dev/null | awk 'END {print (NR>0) ? NR-1 : 0}'; }   # tanpa header

# Proses dengan CPU tertinggi -> "pid|uid|cpu|nama". Agen sendiri, induknya, dan
# proses bantunya dilewati.
find_top_process() {
    ps -eo pid=,ppid=,uid=,pcpu=,comm= --sort=-pcpu 2>/dev/null | awk \
        -v anc="$ANCESTORS" -v me="$$" -v helper="$HELPER_RE" '
        BEGIN { n=split(anc, a, " "); for (i=1;i<=n;i++) isanc[a[i]]=1 }
        {
            name=$5; for (i=6;i<=NF;i++) name=name "_" $i
            if ($1 in isanc || $2==me || name ~ helper) next
            gsub(/[,|]/, "", name)
            print $1 "|" $3 "|" $4 "|" name
            exit
        }'
}

# ---- Evaluasi ambang batas & Auto-Action ---------------------------------------
level_of() {        # $1=nilai $2=warn $3=crit -> LEVEL (0 OK, 1 WARNING, 2 CRITICAL)
    LEVEL=0
    if [ "$1" -ge "$3" ]; then LEVEL=2; elif [ "$1" -ge "$2" ]; then LEVEL=1; fi
}

is_actionable() {   # $1=uid $2=nama : hanya proses user-space non-sistem
    [ "$1" -ge "$MIN_ACTION_UID" ] || return 1
    [[ "$2" =~ $PROTECTED_RE ]] && return 1
    return 0
}

auto_action() {     # dipanggil saat sensor CPU >= WARNING
    ACTION_STATUS=""
    [[ "$TOP_PID" =~ ^[0-9]+$ ]] || return 0
    is_actionable "$TOP_UID" "$TOP_PROC" || return 0
    awk -v c="$TOP_CPU" -v m="$MIN_ACTION_CPU" 'BEGIN { exit !(c+0 >= m+0) }' || return 0

    local state="${RENICED[$TOP_PID]:-}" lvl=WARNING
    [ "${LV[CPU]}" -ge 2 ] && lvl=CRITICAL
    if [ -z "$state" ]; then
        if renice -n "$RENICE_VALUE" -p "$TOP_PID" >/dev/null 2>&1; then
            RENICED[$TOP_PID]=ok
            ACTION_STATUS="${lvl}_RENICED"
            write_alert WARNING "CPU=${CPU}% melewati batas ${CPU_WARN}%. Proses '$TOP_PROC' (PID $TOP_PID) di-renice ke nice $RENICE_VALUE."
        else
            RENICED[$TOP_PID]=fail
            write_alert WARNING "CPU=${CPU}% tinggi, tetapi renice '$TOP_PROC' (PID $TOP_PID) ditolak (izin tidak cukup)."
        fi
    elif [ "$state" = ok ]; then
        ACTION_STATUS="${lvl}_RENICED"     # sudah ditertibkan, masih diawasi
        if [ "$AUTO_KILL" = 1 ] && [ "$CPU" -ge "$CPU_CRIT" ]; then
            if kill -TERM "$TOP_PID" 2>/dev/null; then
                unset 'RENICED[$TOP_PID]'
                ACTION_STATUS="CRITICAL_KILLED"
                write_alert CRITICAL "CPU=${CPU}% >= ${CPU_CRIT}% walau sudah di-renice. Proses '$TOP_PROC' (PID $TOP_PID) dihentikan (SIGTERM)."
            fi
        fi
    fi
}

prune_reniced() {   # buang PID yang sudah tidak ada
    local p
    for p in "${!RENICED[@]}"; do kill -0 "$p" 2>/dev/null || unset 'RENICED[$p]'; done
}

# ---- Startup -------------------------------------------------------------------
require_cmds
validate_config
ensure_lock_file
init_logs

# Induk agen (dan agen sendiri) tidak boleh dianggap "proses teratas"
ANCESTORS=" $$ "
p=$PPID
while [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 1 ]; do
    ANCESTORS+="$p "
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done

trap 'echo; log_info "Agen sensor dihentikan."; exit 0' INT TERM

log_info "PRTG-Lite Sensor Agent aktif (PID $$) | interval ${INTERVAL}s"
log_info "Ambang CPU ${CPU_WARN}/${CPU_CRIT}% | RAM ${MEM_WARN}/${MEM_CRIT}% | Swap ${SWAP_WARN}/${SWAP_CRIT}% | Disk ${DISK_WARN}/${DISK_CRIT}%"
log_info "Auto-action: renice +${RENICE_VALUE} (hanya UID >= ${MIN_ACTION_UID}) | auto-kill: $([ "$AUTO_KILL" = 1 ] && echo AKTIF || echo nonaktif)"
log_info "Log: $CSV_LOG (izin 640) | Tekan Ctrl+C untuk berhenti"
df -T / 2>/dev/null | sed 's/^/[INFO] /'
command -v lsblk >/dev/null 2>&1 && lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | sed 's/^/[INFO] /'

# Pembacaan CPU sudah memakan ~1 detik (vmstat 1 2), jadi tidur INTERVAL-1.
SLEEP_FOR=$(( INTERVAL > 1 ? INTERVAL - 1 : 0 ))
ROTATE_EVERY=20
cycle=0
declare -A LV=()

while true; do
    TS=$(date '+%Y-%m-%d %H:%M:%S')

    CPU=$(read_cpu);            [[ "$CPU" =~ ^[0-9]+$ ]]  || CPU=0
    read -r MEM SWAP < <(read_mem_swap)
    [[ "$MEM" =~ ^[0-9]+$ ]]  || MEM=0
    [[ "$SWAP" =~ ^[0-9]+$ ]] || SWAP=0
    DISK=$(read_disk);          [[ "$DISK" =~ ^[0-9]+$ ]] || DISK=0
    THREADS=$(read_threads);    [[ "$THREADS" =~ ^[0-9]+$ ]] || THREADS=0

    TOP_PID=0; TOP_UID=0; TOP_CPU=0.0; TOP_PROC=none
    IFS='|' read -r TOP_PID TOP_UID TOP_CPU TOP_PROC < <(find_top_process)
    [ -n "${TOP_PID:-}" ] || { TOP_PID=0; TOP_UID=0; TOP_CPU=0.0; TOP_PROC=none; }

    # Level per sensor, lalu status keseluruhan = sensor terburuk
    level_of "$CPU"  "$CPU_WARN"  "$CPU_CRIT";  LV[CPU]=$LEVEL
    level_of "$MEM"  "$MEM_WARN"  "$MEM_CRIT";  LV[MEM]=$LEVEL
    level_of "$SWAP" "$SWAP_WARN" "$SWAP_CRIT"; LV[SWAP]=$LEVEL
    level_of "$DISK" "$DISK_WARN" "$DISK_CRIT"; LV[DISK]=$LEVEL

    WORST=0; WORST_NAME=""
    for s in CPU MEM SWAP DISK; do
        if [ "${LV[$s]}" -gt "$WORST" ]; then WORST=${LV[$s]}; WORST_NAME=$s; fi
    done
    case $WORST in
        0) STATUS="OK" ;;
        1) STATUS="WARNING_$WORST_NAME" ;;
        *) STATUS="CRITICAL_$WORST_NAME" ;;
    esac

    ACTION_STATUS=""
    prune_reniced
    if [ "${LV[CPU]}" -ge 1 ]; then
        auto_action
        [ "$WORST_NAME" = CPU ] && [ -n "$ACTION_STATUS" ] && STATUS="$ACTION_STATUS"
    fi

    # Alert hanya saat status berubah (tidak spam tiap siklus)
    if [ "$STATUS" != "$PREV_STATUS" ]; then
        if [ "$STATUS" = OK ]; then
            write_alert INFO "Semua sensor kembali normal."
        elif [ -z "$ACTION_STATUS" ] || [ "$WORST_NAME" != CPU ]; then
            t_warn="${WORST_NAME}_WARN"; t_crit="${WORST_NAME}_CRIT"
            if [ "$WORST" -ge 2 ]; then lvl=CRITICAL; lim=${!t_crit}; else lvl=WARNING; lim=${!t_warn}; fi
            write_alert "$lvl" "Sensor $WORST_NAME ${!WORST_NAME}% melewati batas ${lim}%."
        fi
        PREV_STATUS="$STATUS"
    fi

    locked_append "$CSV_LOG" "$TS,$CPU,$MEM,$SWAP,$DISK,$THREADS,$TOP_PID,$TOP_PROC,$TOP_CPU,$STATUS"
    echo "[$TS] CPU:${CPU}% | RAM:${MEM}% | SWAP:${SWAP}% | DISK:${DISK}% | Thread:${THREADS} | Top:${TOP_PROC}(${TOP_CPU}%) | ${STATUS}"

    cycle=$(( cycle + 1 ))
    [ $(( cycle % ROTATE_EVERY )) -eq 0 ] && maintain_logs
    sleep "$SLEEP_FOR"
done