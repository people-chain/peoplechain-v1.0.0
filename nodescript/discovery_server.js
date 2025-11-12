"use strict";

// Lightweight discovery/monitor server with embedded UI.
// Endpoints:
//   GET  /              -> Monitor UI
//   GET  /health        -> { ok }
//   GET  /peers         -> [{ nodeId, alias, lastSeen, sent, received, queued }]
//   GET  /stats         -> system + server stats
//   GET  /logs          -> recent activity
//   POST /send          -> { from, to, bytes?, message? } increments counters

const http = require('http');
const os = require('os');

const PORT = Number(process.env.PORT || getArg('--port', 8080));

function getArg(name, def) {
  const i = process.argv.indexOf(name);
  if (i >= 0 && i + 1 < process.argv.length) return process.argv[i + 1];
  return def;
}

const startTime = Date.now();
const peers = new Map(); // id -> { nodeId, alias, lastSeen, sent, received, queued }
let totalSent = 0;
let totalReceived = 0;
let loopLagMs = 0;
let cpuPercent = 0;
const logs = [];

function logEvent(msg) {
  const entry = { t: new Date().toISOString(), msg: String(msg) };
  logs.push(entry);
  if (logs.length > 200) logs.shift();
}

// Event loop lag measurement
let expected = Date.now() + 1000;
setInterval(() => {
  const now = Date.now();
  loopLagMs = Math.max(0, now - expected);
  expected = now + 1000;
}, 1000);

// CPU usage estimate across cores
let lastCpu = process.cpuUsage();
let lastHr = process.hrtime.bigint();
setInterval(() => {
  try {
    const curCpu = process.cpuUsage();
    const curHr = process.hrtime.bigint();
    const userDiff = curCpu.user - lastCpu.user; // microseconds
    const sysDiff = curCpu.system - lastCpu.system; // microseconds
    const wallUs = Number(curHr - lastHr) / 1000; // microseconds
    const cores = Math.max(1, (os.cpus() && os.cpus().length) || 1);
    const usedUs = Math.max(0, userDiff + sysDiff);
    const pct = (usedUs / (wallUs * cores)) * 100;
    cpuPercent = Math.max(0, Math.min(100, Math.round(pct)));
    lastCpu = curCpu;
    lastHr = curHr;
  } catch (_) { /* ignore */ }
}, 1000);

function upsertPeer(id) {
  let p = peers.get(id);
  if (!p) {
    p = { nodeId: id, alias: '', lastSeen: Date.now(), sent: 0, received: 0, queued: 0 };
    peers.set(id, p);
  }
  return p;
}

function json(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body)
  });
  res.end(body);
}

function serveMonitor(res) {
  const MONITOR_HTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Discovery Monitor</title>
  <style>
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin: 16px; background:#0b1020; color:#f2f4f8; }
    h1 { margin: 0 0 12px 0; font-size: 20px; }
    .row { display:flex; gap:12px; align-items:center; flex-wrap:wrap; }
    .card { background:#141b34; border-radius:12px; padding:12px; border:1px solid rgba(255,255,255,0.06); }
    table { width:100%; border-collapse: collapse; }
    th, td { padding:8px 10px; text-align:left; font-size:13px; }
    thead th { position: sticky; top:0; background:#11182f; }
    tbody tr { border-bottom:1px dashed rgba(255,255,255,0.06); }
    .fresh { color:#37d67a; }
    .warm { color:#f5a623; }
    .stale { color:#9aa0aa; }
    .pill { display:inline-block; padding:2px 8px; border-radius:999px; background:#1d274d; font-size:12px; }
    input, button, select { background:#0f1530; color:#e8ebf2; border:1px solid rgba(255,255,255,0.08); border-radius:8px; padding:8px 10px; }
    button.primary { background:#3a6df0; border-color:#3a6df0; color:white; }
    a { color:#8ab4ff; text-decoration:none; }
    .grid { display:grid; grid-template-columns: repeat(auto-fit,minmax(240px,1fr)); gap:12px; }
    .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    .muted { color:#a5abbd; }
  </style>
</head>
<body>
  <div class="row">
    <h1>Discovery Monitor</h1>
    <span id="uptime" class="pill">uptime: —</span>
    <span id="sys" class="pill">cpu: —, mem: —</span>
    <span class="pill"><a href="/health" target="_blank">health</a></span>
  </div>
  <div class="grid" style="margin-top:12px">
    <div class="card">
      <div class="row" style="justify-content:space-between">
        <strong>Peers</strong>
        <span class="muted" id="peerCount">—</span>
      </div>
      <div style="overflow:auto; max-height: 45vh; margin-top:8px">
        <table>
          <thead><tr>
            <th>Status</th><th>ID</th><th>Alias</th><th>Last Seen</th>
            <th>Sent</th><th>Received</th><th>Queued</th>
          </tr></thead>
          <tbody id="peersBody"></tbody>
        </table>
      </div>
    </div>
    <div class="card">
      <strong>Message Tester</strong>
      <div style="margin-top:8px; display:grid; gap:8px">
        <input id="fromId" placeholder="From Node ID" />
        <input id="toId" placeholder="To Node ID" />
        <input id="msg" placeholder="Message (optional)" />
        <button class="primary" onclick="sendMsg()">Send</button>
        <div id="sendResult" class="muted"></div>
      </div>
    </div>
    <div class="card">
      <strong>Activity</strong>
      <div id="logs" class="mono" style="margin-top:8px; max-height:45vh; overflow:auto; white-space:pre-wrap"></div>
    </div>
  </div>
  <script>
    function fmtSecs(s){ s=Math.floor(s); var m=Math.floor(s/60); var r=s%60; var h=Math.floor(m/60); var mm=m%60; if(h>0) return h+"h "+mm+"m "+r+"s"; if(m>0) return m+"m "+r+"s"; return r+"s"; }
    function clsForAge(ms){ if(ms < 30000) return "fresh"; if(ms < 300000) return "warm"; return "stale"; }
    async function refresh(){
      try {
        const [statsRes, peersRes, logsRes] = await Promise.all([
          fetch("/stats"), fetch("/peers"), fetch("/logs")
        ]);
        const stats = await statsRes.json();
        const peers = await peersRes.json();
        const lines = await logsRes.json();
        document.getElementById("uptime").innerText = "uptime: "+fmtSecs(stats.uptimeSec)
          + ", peers: "+peers.length+", sent: "+stats.totalSent+", recv: "+stats.totalReceived;
        document.getElementById("sys").innerText = "cpu: "+stats.cpu.percent+"% | mem: "+stats.memory.rssMb+"MB | lag: "+stats.loopLagMs+"ms";
        document.getElementById("peerCount").innerText = peers.length+" online";
        var rows = "";
        var now = Date.now();
        for (var i=0;i<peers.length;i++) {
          var p = peers[i];
          var age = now - new Date(p.lastSeen).getTime();
          var cls = clsForAge(age);
          rows += '<tr class="' + cls + '">' +
                  '<td class="' + cls + '">●</td>' +
                  '<td class="mono">' + (p.nodeId || '') + '</td>' +
                  '<td>' + (p.alias || '') + '</td>' +
                  '<td>' + Math.floor(age/1000) + 's ago</td>' +
                  '<td>' + (p.sent||0) + '</td>' +
                  '<td>' + (p.received||0) + '</td>' +
                  '<td>' + (p.queued||0) + '</td>' +
                '</tr>';
        }
        document.getElementById("peersBody").innerHTML = rows;
        document.getElementById("logs").innerText = lines.map(l => "["+l.t+"] "+l.msg).join("\n");
      } catch(e){ console.error(e); }
    }
    async function sendMsg(){
      var from = document.getElementById("fromId").value.trim();
      var to = document.getElementById("toId").value.trim();
      var msg = document.getElementById("msg").value;
      const res = await fetch("/send", { method:"POST", headers:{"Content-Type":"application/json"}, body: JSON.stringify({from:from, to:to, message:msg}) });
      const j = await res.json();
      document.getElementById("sendResult").innerText = JSON.stringify(j);
      refresh();
    }
    refresh(); setInterval(refresh, 2000);
  </script>
</body>
</html>`;

  const body = MONITOR_HTML;
  const buf = Buffer.from(body, 'utf8');
  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Content-Length': buf.length
  });
  res.end(buf);
}

const server = http.createServer(async (req, res) => {
  try {
    // Use WHATWG URL API to avoid deprecated url.parse warnings.
    // Fallback to localhost if Host header is missing.
    const base = `http://${req.headers.host || ('localhost:' + PORT)}`;
    const parsed = new URL(req.url, base);
    const path = parsed.pathname || '/';
    if (req.method === 'GET' && (path === '/' || path === '/index.html')) {
      return serveMonitor(res);
    }
    if (req.method === 'GET' && path === '/health') {
      return json(res, 200, { ok: true });
    }
    if (req.method === 'GET' && path === '/peers') {
      const list = Array.from(peers.values()).sort((a,b) => b.lastSeen - a.lastSeen);
      return json(res, 200, list);
    }
    if (req.method === 'GET' && path === '/logs') {
      return json(res, 200, logs.slice(-100));
    }
    if (req.method === 'GET' && path === '/stats') {
      const mu = process.memoryUsage();
      const stats = {
        uptimeSec: Math.floor((Date.now() - startTime) / 1000),
        totalSent,
        totalReceived,
        loopLagMs,
        cpu: { percent: cpuPercent },
        memory: {
          rssMb: Math.round(mu.rss / (1024*1024)),
          heapUsedMb: Math.round(mu.heapUsed / (1024*1024)),
          heapTotalMb: Math.round(mu.heapTotal / (1024*1024))
        },
        platform: { platform: os.platform(), release: os.release(), arch: os.arch(), cores: (os.cpus() && os.cpus().length) || 1 }
      };
      return json(res, 200, stats);
    }
    if (req.method === 'POST' && path === '/send') {
      const body = await readBodyJson(req);
      const from = String(body.from || '').trim();
      const to = String(body.to || '').trim();
      const bytes = Number(body.bytes || 0);
      const message = String(body.message || '');
      if (!from || !to) return json(res, 400, { ok:false, error: 'from and to are required' });
      const pFrom = upsertPeer(from); pFrom.sent += (bytes || message.length || 1); pFrom.lastSeen = Date.now();
      const pTo = upsertPeer(to);   pTo.received += (bytes || message.length || 1); pTo.lastSeen = Date.now();
      totalSent += (bytes || message.length || 1); totalReceived += (bytes || message.length || 1);
      logEvent('send from '+from+' to '+to+' ('+(bytes || message.length || 1)+' bytes)');
      return json(res, 200, { ok:true, from: pFrom, to: pTo });
    }
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('not found');
  } catch (e) {
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end('error: ' + e.message);
  }
});

server.listen(PORT, () => {
  logEvent('server started on http://0.0.0.0:'+PORT+'/');
  console.log('[info] Discovery server listening on port', PORT);
});

function readBodyJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => { data += chunk; if (data.length > 5*1024*1024) { reject(new Error('body too large')); req.destroy(); } });
    req.on('end', () => {
      try { resolve(data ? JSON.parse(data) : {}); } catch (e) { reject(e); }
    });
    req.on('error', reject);
  });
}
