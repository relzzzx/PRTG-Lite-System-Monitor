#!/usr/bin/env python3
import http.server
import socketserver
import json
import os

PORT = 8080
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_LOG = os.path.join(BASE_DIR, "logs", "sysmon.csv")
ALERT_LOG = os.path.join(BASE_DIR, "logs", "alerts.log")

HTML_PAGE = """<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <title>PRTG-Lite OS Resource Monitor</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 20px; }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #334155; padding-bottom: 10px; margin-bottom: 20px; }
        .cards { display: grid; grid-template-columns: repeat(5, 1fr); gap: 15px; margin-bottom: 20px; }
        .card { background: #1e293b; padding: 15px; border-radius: 8px; border-left: 5px solid #22c55e; }
        .card.warn { border-left-color: #ef4444; background: #3b1c22; }
        .card h4 { margin: 0 0 5px 0; color: #94a3b8; font-size: 13px; }
        .card .val { font-size: 26px; font-weight: bold; }
        .grid-main { display: grid; grid-template-columns: 2fr 1fr; gap: 20px; }
        .panel { background: #1e293b; padding: 15px; border-radius: 8px; }
        pre { background: #090d16; padding: 10px; border-radius: 6px; color: #f87171; font-size: 12px; height: 220px; overflow-y: auto; white-space: pre-wrap; }
    </style>
</head>
<body>
    <div class="header">
        <div>
            <h2 style="margin:0;">PRTG-Lite: Sistem Operasi Sensor Dashboard</h2>
            <small style="color:#94a3b8;">TIK103 Proyek Sistem Operasi - Live Probe Sensor</small>
        </div>
        <div id="status-badge" style="padding: 8px 16px; border-radius: 6px; background: #22c55e; font-weight: bold;">STATUS: OK</div>
    </div>
    <div class="cards">
        <div class="card" id="c-cpu"><h4>SENSOR CPU</h4><div class="val" id="v-cpu">0%</div></div>
        <div class="card" id="c-mem"><h4>SENSOR RAM</h4><div class="val" id="v-mem">0%</div></div>
        <div class="card" id="c-swap"><h4>SENSOR SWAP</h4><div class="val" id="v-swap">0%</div></div>
        <div class="card" id="c-disk"><h4>SENSOR DISK (/)</h4><div class="val" id="v-disk">0%</div></div>
        <div class="card"><h4>ACTIVE THREADS</h4><div class="val" id="v-thr">0</div></div>
    </div>
    <div class="grid-main">
        <div class="panel">
            <h4 style="margin-top:0;">Live Sensor Channels (CPU, RAM, Swap %)</h4>
            <canvas id="liveChart" height="110"></canvas>
        </div>
        <div class="panel">
            <h4 style="margin-top:0;">Top Process & Log Mitigasi Otomatis (Auto-Renice)</h4>
            <p id="top-proc" style="font-size:14px; color:#38bdf8;">Menunggu data...</p>
            <pre id="alert-box">Belum ada peringatan ambang batas.</pre>
        </div>
    </div>
<script>
const ctx = document.getElementById('liveChart').getContext('2d');
const chart = new Chart(ctx, {
    type: 'line',
    data: { labels: [], datasets: [
        { label: 'CPU %', data: [], borderColor: '#38bdf8', tension: 0.3 },
        { label: 'RAM %', data: [], borderColor: '#a855f7', tension: 0.3 },
        { label: 'Swap %', data: [], borderColor: '#eab308', tension: 0.3 }
    ]},
    options: { scales: { y: { min: 0, max: 100 } }, animation: false }
});

async function fetchMetrics() {
    const res = await fetch('/api/metrics');
    const data = await res.json();
    if (!data.rows.length) return;
    const last = data.rows[data.rows.length - 1];
    document.getElementById('v-cpu').innerText = last.cpu + '%';
    document.getElementById('v-mem').innerText = last.mem + '%';
    document.getElementById('v-swap').innerText = last.swap + '%';
    document.getElementById('v-disk').innerText = last.disk + '%';
    document.getElementById('v-thr').innerText = last.threads;
    document.getElementById('top-proc').innerText = `Proses Tertinggi: ${last.top_proc} (PID: ${last.top_pid}) - ${last.top_cpu}% CPU`;

    document.getElementById('c-cpu').className = last.cpu >= 75 ? 'card warn' : 'card';
    const badge = document.getElementById('status-badge');
    badge.innerText = 'STATUS: ' + last.status;
    badge.style.background = last.status === 'OK' ? '#22c55e' : '#ef4444';

    chart.data.labels = data.rows.map(r => r.timestamp.split(' ')[1]);
    chart.data.datasets[0].data = data.rows.map(r => r.cpu);
    chart.data.datasets[1].data = data.rows.map(r => r.mem);
    chart.data.datasets[2].data = data.rows.map(r => r.swap);
    chart.update();

    if (data.alerts) document.getElementById('alert-box').innerText = data.alerts;
}
setInterval(fetchMetrics, 3000);
fetchMetrics();
</script>
</body>
</html>
"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/metrics':
            rows = []
            if os.path.exists(CSV_LOG):
                with open(CSV_LOG, 'r') as f:
                    lines = f.read().strip().split('\n')[1:][-20:]
                    for line in lines:
                        p = line.split(',')
                        if len(p) >= 10:
                            rows.append({
                                "timestamp": p[0], "cpu": float(p[1]), "mem": float(p[2]),
                                "swap": float(p[3]), "disk": float(p[4]), "threads": int(p[5]),
                                "top_pid": p[6], "top_proc": p[7], "top_cpu": p[8], "status": p[9]
                            })
            alerts = ""
            if os.path.exists(ALERT_LOG):
                with open(ALERT_LOG, 'r') as af:
                    alerts = "".join(af.readlines()[-10:])
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"rows": rows, "alerts": alerts}).encode())
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode())
    def log_message(self, format, *args):
        return

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    print(f"[INFO] PRTG-Lite Web Dashboard aktif di http://0.0.0.0:{PORT}")
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        httpd.serve_forever()