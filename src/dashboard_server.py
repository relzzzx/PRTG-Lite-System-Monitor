#!/usr/bin/env python3
"""PRTG-Lite OS Monitor - Web Dashboard Server.

Membaca logs/sysmon.csv & logs/alerts.log (hasil sensor_agent.sh) dan
menyajikannya sebagai dashboard web di 0.0.0.0:8080 (akses lewat Host-Only).

Endpoint:
    GET /              -> dashboard (src/web/index.html)
    GET /api/metrics   -> JSON metrik, status per sensor, alert (?n=60)

Pembacaan log memakai flock bersama (LOCK_SH) pada berkas kunci yang sama
dengan agen sensor, sehingga tidak terjadi race condition (Praktikum 5).
"""
from __future__ import annotations

import csv
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from collections import deque
from contextlib import contextmanager
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from itertools import chain
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SRC_DIR = Path(__file__).resolve().parent
BASE_DIR = SRC_DIR.parent
WEB_DIR = SRC_DIR / "web"
CONF_FILE = Path(os.environ.get("PRTG_CONF", SRC_DIR / "prtg.conf"))
LOG_DIR = Path(os.environ.get("PRTG_LOG_DIR", BASE_DIR / "logs"))
CSV_LOG = LOG_DIR / "sysmon.csv"
ALERT_LOG = LOG_DIR / "alerts.log"

HOST = "0.0.0.0"  # wajib 0.0.0.0 agar bisa diakses dari Windows via Host-Only
PORT = int(os.environ.get("PRTG_PORT", "8080"))
DEFAULT_POINTS = 60
MAX_POINTS = 300
ALERT_LINES = 12

CONF_DEFAULTS = {
    "INTERVAL": 5,
    "CPU_WARN": 80, "CPU_CRIT": 95,
    "MEM_WARN": 80, "MEM_CRIT": 90,
    "SWAP_WARN": 50, "SWAP_CRIT": 80,
    "DISK_WARN": 80, "DISK_CRIT": 90,
    "LOCK_FILE": "/tmp/sysmon.lock",
}

# Nama kolom proposal (Tabel 5) -> nama internal; nama lama tetap diterima
COLUMN_ALIASES = {
    "cpu_usage": "cpu", "mem_usage": "mem", "swap_usage": "swap",
    "disk_usage": "disk", "total_threads": "threads",
    "top_proc_name": "top_proc", "top_proc_cpu": "top_cpu",
}
DEFAULT_COLUMNS = ["timestamp", "cpu", "mem", "swap", "disk", "threads",
                   "top_pid", "top_proc", "top_cpu", "status"]

STATIC_ROUTES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
}

ALERT_RE = re.compile(r"^\[(?P<ts>[^\]]+)\]\s*(?P<level>INFO|WARNING|CRITICAL)\b[^:]*:?\s*(?P<msg>.*)$")


# --------------------------------------------------------------------------- #
# Konfigurasi & pembacaan log
# --------------------------------------------------------------------------- #
def load_conf() -> dict:
    """Baca src/prtg.conf (KUNCI=NILAI); nilai tidak valid memakai default."""
    conf = dict(CONF_DEFAULTS)
    try:
        text = CONF_FILE.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return conf
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip().strip("'\"")
        if key not in conf:
            continue
        if isinstance(CONF_DEFAULTS[key], int):
            if value.isdigit():
                conf[key] = int(value)
        elif value:
            conf[key] = value
    return conf


@contextmanager
def shared_lock(lock_path: str):
    """flock LOCK_SH pada berkas kunci agen. Bila tidak tersedia, tetap membaca."""
    fd = None
    try:
        fd = os.open(lock_path, os.O_RDONLY)
        deadline = time.monotonic() + 1.0
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    break  # jangan menggantung bila agen menahan kunci terlalu lama
                time.sleep(0.02)
    except OSError:
        pass  # berkas kunci belum ada / tidak boleh dibaca
    try:
        yield
    finally:
        if fd is not None:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)


def _to_float(value: str, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def parse_row(cells: list[str], columns: list[str]) -> dict | None:
    """Ubah satu baris CSV menjadi dict; baris terpotong/rusak -> None."""
    if len(cells) < len(columns):
        return None
    d = dict(zip(columns, (c.strip() for c in cells)))
    try:
        return {
            "timestamp": d["timestamp"],
            "cpu": float(d["cpu"]), "mem": float(d["mem"]),
            "swap": float(d["swap"]), "disk": float(d["disk"]),
            "threads": int(float(d["threads"])),
            "top_pid": d["top_pid"], "top_proc": d["top_proc"],
            "top_cpu": _to_float(d["top_cpu"]),
            "status": d.get("status") or "OK",
        }
    except (KeyError, ValueError):
        return None


def read_rows(limit: int, lock_path: str) -> list[dict]:
    if not CSV_LOG.exists():
        return []
    with shared_lock(lock_path):
        try:
            with CSV_LOG.open("r", encoding="utf-8", errors="replace", newline="") as fh:
                reader = csv.reader(fh)
                first = next(reader, None)
                if first is None:
                    return []
                if first and first[0].strip().lower() == "timestamp":
                    columns = [COLUMN_ALIASES.get(c.strip(), c.strip()) for c in first]
                    tail = deque(reader, maxlen=limit)
                else:  # tanpa header
                    columns = DEFAULT_COLUMNS
                    tail = deque(chain([first], reader), maxlen=limit)
        except OSError:
            return []
    rows = (parse_row(cells, columns) for cells in tail)
    return [r for r in rows if r]


def read_alerts(limit: int, lock_path: str) -> list[dict]:
    if not ALERT_LOG.exists():
        return []
    with shared_lock(lock_path):
        try:
            with ALERT_LOG.open("r", encoding="utf-8", errors="replace") as fh:
                lines = list(deque(fh, maxlen=limit))
        except OSError:
            return []
    alerts = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        m = ALERT_RE.match(line)
        if m:
            alerts.append({"time": m["ts"], "level": m["level"], "message": m["msg"]})
        else:
            alerts.append({"time": "", "level": "INFO", "message": line})
    return alerts


# --------------------------------------------------------------------------- #
# Status sensor (Up / Warning / Critical)
# --------------------------------------------------------------------------- #
def sensor_state(value: float, warn: int, crit: int) -> str:
    if value >= crit:
        return "critical"
    if value >= warn:
        return "warning"
    return "up"


def state_from_status(status: str) -> str:
    s = status.upper()
    if "CRITICAL" in s:
        return "critical"
    if "WARN" in s:
        return "warning"
    return "up"


def build_payload(points: int) -> dict:
    conf = load_conf()
    lock_path = str(conf["LOCK_FILE"])
    rows = read_rows(points, lock_path)
    alerts = read_alerts(ALERT_LINES, lock_path)
    thresholds = {k: {"warn": conf[f"{k.upper()}_WARN"], "crit": conf[f"{k.upper()}_CRIT"]}
                  for k in ("cpu", "mem", "swap", "disk")}
    payload = {
        "rows": rows, "alerts": alerts, "thresholds": thresholds,
        "interval": conf["INTERVAL"], "latest": None,
        "server_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }
    if not rows:
        return payload

    last = rows[-1]
    states = {k: sensor_state(last[k], thresholds[k]["warn"], thresholds[k]["crit"])
              for k in thresholds}
    states["threads"] = "up"  # proposal tidak mendefinisikan ambang untuk thread
    try:
        age = max(0, int((datetime.now() - datetime.strptime(last["timestamp"], "%Y-%m-%d %H:%M:%S")).total_seconds()))
    except ValueError:
        age = None
    status = last["status"].upper()
    action = "renice" if "RENICED" in status else "kill" if "KILLED" in status else None
    payload["latest"] = {
        **last,
        "states": states,
        "overall": state_from_status(last["status"]),
        "action": action,
        "age_seconds": age,
        "summary": {s: sum(1 for v in states.values() if v == s)
                    for s in ("up", "warning", "critical")},
    }
    return payload


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #
class Handler(BaseHTTPRequestHandler):
    server_version = "PRTGLite/1.0"

    def _send(self, status: int, body: bytes, ctype: str, no_store: bool = False) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        if no_store:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, status: int, obj: dict) -> None:
        self._send(status, json.dumps(obj).encode("utf-8"), "application/json", no_store=True)

    def do_GET(self) -> None:  # noqa: N802 (nama method ditentukan http.server)
        url = urlparse(self.path)
        try:
            if url.path == "/api/metrics":
                try:
                    n = int(parse_qs(url.query).get("n", [DEFAULT_POINTS])[0])
                except ValueError:
                    n = DEFAULT_POINTS
                self._send_json(HTTPStatus.OK, build_payload(max(1, min(n, MAX_POINTS))))
            elif url.path in STATIC_ROUTES:
                fname, ctype = STATIC_ROUTES[url.path]
                self._send(HTTPStatus.OK, (WEB_DIR / fname).read_bytes(), ctype, no_store=True)
            else:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
        except (BrokenPipeError, ConnectionResetError):
            pass  # browser menutup koneksi lebih dulu
        except Exception as exc:  # satu request gagal tidak boleh mematikan server
            print(f"[ERROR] {self.path}: {exc!r}", file=sys.stderr)
            try:
                self._send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "internal error"})
            except OSError:
                pass

    def log_message(self, fmt: str, *args) -> None:  # senyap; error tetap ke stderr
        return


def local_ipv4_addresses() -> list[str]:
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr", "show"], capture_output=True,
                             text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    ips = (m.group(1) for m in re.finditer(r"inet (\d+\.\d+\.\d+\.\d+)", out))
    return [ip for ip in ips if not ip.startswith("127.")]


def main() -> int:
    if not (WEB_DIR / "index.html").exists():
        print(f"[ERROR] Berkas dashboard tidak ditemukan di {WEB_DIR}", file=sys.stderr)
        return 1
    try:
        httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    except OSError as exc:
        print(f"[ERROR] Tidak bisa bind {HOST}:{PORT} - {exc}", file=sys.stderr)
        return 1
    httpd.daemon_threads = True
    print(f"[INFO] PRTG-Lite Web Dashboard aktif di http://{HOST}:{PORT}")
    for ip in local_ipv4_addresses():
        print(f"[INFO]   buka dari Windows Host: http://{ip}:{PORT}")
    print(f"[INFO] Membaca log dari: {LOG_DIR}  (Ctrl+C untuk berhenti)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[INFO] Dashboard dihentikan.")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
