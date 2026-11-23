'use strict';
/* PRTG-Lite OS Monitor - logika dashboard. Semua teks dinamis memakai textContent. */

const POLL_MS = 3000;
const FETCH_TIMEOUT_MS = 4000;
const WINDOW_POINTS = 60;
const MUTED = '#7d8597';
const COLORS = { ok: '#34d399', warn: '#f5a524', crit: '#f0525a', accent: '#8b86ff', cyan: '#38bdf8' };
const STATE_TEXT = { up: 'Up', warning: 'Warning', critical: 'Critical' };
const LEVEL_TEXT = { INFO: 'Info', WARNING: 'Warning', CRITICAL: 'Critical' };

const $ = (id) => document.getElementById(id);
const charts = {};
let chartJsReady = false;

/* ---------- Chart helpers ---------- */
function areaFill(color) {
  return (ctx) => {
    const { chart } = ctx;
    const area = chart.chartArea;
    if (!area) return 'transparent';
    const g = chart.ctx.createLinearGradient(0, area.top, 0, area.bottom);
    g.addColorStop(0, color + '45');
    g.addColorStop(1, color + '00');
    return g;
  };
}

function lineDataset(label, color, extra = {}) {
  return { label, data: [], borderColor: color, backgroundColor: areaFill(color), fill: true,
           tension: 0.4, borderWidth: 2, pointRadius: 0, pointHoverRadius: 4, ...extra };
}

function makeLineChart(canvasId, datasets, showLegend) {
  return new Chart($(canvasId), {
    type: 'line',
    data: { labels: [], datasets },
    options: {
      responsive: true, maintainAspectRatio: false, animation: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: showLegend, align: 'end',
                  labels: { color: MUTED, usePointStyle: true, boxWidth: 8, boxHeight: 8, font: { size: 11 } } },
        tooltip: { backgroundColor: '#161a24', borderColor: '#262c3a', borderWidth: 1,
                   titleColor: '#e8eaf0', bodyColor: '#c9cedb',
                   callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.y}%` } },
      },
      scales: {
        x: { grid: { display: false }, border: { display: false },
             ticks: { color: MUTED, maxTicksLimit: 6, maxRotation: 0, font: { size: 10 } } },
        y: { min: 0, max: 100, border: { display: false }, grid: { color: 'rgba(255,255,255,.05)' },
             ticks: { color: MUTED, stepSize: 25, callback: (v) => v + '%', font: { size: 10 } } },
      },
    },
  });
}

function initCharts() {
  if (typeof Chart === 'undefined') {
    document.querySelectorAll('.chart-box, .donut').forEach((box) => {
      const note = document.createElement('div');
      note.className = 'chart-fallback';
      note.textContent = 'Chart.js gagal dimuat. Browser perlu akses internet ke cdn.jsdelivr.net.';
      box.appendChild(note);
    });
    return;
  }
  chartJsReady = true;
  charts.cpu = makeLineChart('chart-cpu', [
    lineDataset('CPU', COLORS.ok),
    lineDataset('Batas Warning', COLORS.warn, { fill: false, borderDash: [5, 5], borderWidth: 1.2, pointHoverRadius: 0 }),
  ], false);
  charts.mem = makeLineChart('chart-mem', [
    lineDataset('RAM', COLORS.accent),
    lineDataset('Swap', COLORS.cyan, { backgroundColor: 'transparent', fill: false }),
  ], true);
  charts.donut = new Chart($('chart-donut'), {
    type: 'doughnut',
    data: { labels: ['Up', 'Warning', 'Critical'],
            datasets: [{ data: [1, 0, 0], backgroundColor: [COLORS.ok, COLORS.warn, COLORS.crit], borderWidth: 0, spacing: 2 }] },
    options: { cutout: '74%', animation: false, plugins: { legend: { display: false } } },
  });
}

/* ---------- Render ---------- */
function setState(el, state) {
  el.classList.remove('s-up', 's-warning', 's-critical');
  el.classList.add('s-' + state);
  const chip = el.querySelector('.chip');
  if (chip) chip.textContent = STATE_TEXT[state];
}

function deltaText(diff, unit) {
  if (diff === 0) return '• stabil dari sampel sebelumnya';
  return `${diff > 0 ? '▲' : '▼'} ${Math.abs(diff)}${unit} dari sampel sebelumnya`;
}

function renderSensors(data) {
  const { rows, latest } = data;
  const prev = rows.length > 1 ? rows[rows.length - 2] : latest;
  const maxThreads = Math.max(...rows.map((r) => r.threads), 1);
  document.querySelectorAll('.stat').forEach((card) => {
    const key = card.dataset.sensor;
    const value = latest[key];
    card.querySelector('.stat-val b').textContent = Math.round(value);
    card.querySelector('.stat-delta').textContent =
      deltaText(Math.round(value - prev[key]), key === 'threads' ? '' : '%');
    const pct = key === 'threads' ? Math.min(100, (value / (maxThreads * 1.25)) * 100) : Math.min(100, value);
    card.querySelector('.gauge span').style.height = pct + '%';
    setState(card, latest.states[key]);
  });
}

function renderOverall(latest) {
  setState($('overall'), latest.overall);
  $('overall-code').textContent = latest.status;
}

function renderCharts(data) {
  if (!chartJsReady) return;
  const { rows, thresholds } = data;
  const labels = rows.map((r) => r.timestamp.split(' ')[1] || r.timestamp);
  charts.cpu.data.labels = labels;
  charts.cpu.data.datasets[0].data = rows.map((r) => r.cpu);
  charts.cpu.data.datasets[1].data = rows.map(() => thresholds.cpu.warn);
  charts.cpu.update();
  charts.mem.data.labels = labels;
  charts.mem.data.datasets[0].data = rows.map((r) => r.mem);
  charts.mem.data.datasets[1].data = rows.map((r) => r.swap);
  charts.mem.update();
  const span = `${rows.length} sampel terakhir`;
  $('cpu-range').textContent = span;
  $('mem-range').textContent = span;
}

function renderDonut(summary) {
  ['up', 'warning', 'critical'].forEach((k) => { $('lg-' + k).textContent = summary[k]; });
  $('donut-total').textContent = summary.up + summary.warning + summary.critical;
  if (!chartJsReady) return;
  charts.donut.data.datasets[0].data = [summary.up, summary.warning, summary.critical];
  charts.donut.update();
}

function renderAlerts(alerts) {
  const list = $('alert-list');
  list.replaceChildren();
  $('alert-count').textContent = alerts.length ? `${alerts.length} terbaru` : '0';
  if (!alerts.length) {
    const li = document.createElement('li');
    li.className = 'empty';
    li.textContent = 'Belum ada peringatan ambang batas.';
    list.appendChild(li);
    return;
  }
  alerts.slice().reverse().forEach((a) => {
    const li = document.createElement('li');
    li.className = 'lv-' + a.level;
    const dot = document.createElement('span');
    dot.className = 'dot';
    const body = document.createElement('div');
    const msg = document.createElement('span');
    msg.className = 'alert-msg';
    msg.textContent = a.message;
    const time = document.createElement('span');
    time.className = 'alert-time';
    time.textContent = a.time;
    body.append(msg, time);
    const chip = document.createElement('span');
    chip.className = 'lv-chip';
    chip.textContent = LEVEL_TEXT[a.level] || a.level;
    li.append(dot, body, chip);
    list.appendChild(li);
  });
}

function renderProcess(latest) {
  $('top-name').textContent = latest.top_proc;
  $('top-meta').textContent = `PID ${latest.top_pid} · ${latest.top_cpu}% CPU`;
  const act = { renice: ['Renice aktif', 'Prioritas proses diturunkan (renice)'],
                kill: ['Proses dihentikan', 'Dihentikan dengan SIGTERM karena CPU kritis'] }[latest.action];
  $('act-name').textContent = act ? act[0] : 'Standby';
  $('act-meta').textContent = act ? act[1] : 'Belum ada proses ditertibkan';
}

function renderFreshness(data) {
  const el = $('last-update');
  const { latest, interval } = data;
  const age = latest.age_seconds;
  const stale = age !== null && age > interval * 3;
  el.textContent = `Update terakhir ${latest.timestamp.split(' ')[1]}` +
    (age !== null ? ` (${age} dtk lalu)` : '') + (stale ? ' · data tidak diperbarui, cek sensor_agent.sh' : '');
  el.classList.toggle('stale', stale);
}

function render(data) {
  renderAlerts(data.alerts);
  if (!data.latest) {
    $('last-update').textContent = 'Menunggu data dari sensor_agent.sh…';
    return;
  }
  renderSensors(data);
  renderOverall(data.latest);
  renderCharts(data);
  renderDonut(data.latest.summary);
  renderProcess(data.latest);
  renderFreshness(data);
}

function setConn(ok) {
  const el = $('conn');
  el.classList.toggle('on', ok);
  el.classList.toggle('off', !ok);
  $('conn-text').textContent = ok ? 'Terhubung' : 'Terputus';
}

/* ---------- Polling ---------- */
async function tick() {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(`/api/metrics?n=${WINDOW_POINTS}`, { cache: 'no-store', signal: ctl.signal });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    render(await res.json());
    setConn(true);
  } catch (err) {
    setConn(false);
  } finally {
    clearTimeout(timer);
    setTimeout(tick, POLL_MS);
  }
}

/* ---------- Sidebar: tandai menu aktif ---------- */
function initNav() {
  const links = [...document.querySelectorAll('.nav a')];
  links.forEach((a) => a.addEventListener('click', () => {
    links.forEach((l) => l.classList.toggle('active', l === a));
  }));
}

window.addEventListener('DOMContentLoaded', () => {
  initNav();
  initCharts();
  tick();
});
