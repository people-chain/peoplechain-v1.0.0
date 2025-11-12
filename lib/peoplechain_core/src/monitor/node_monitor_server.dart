// Lightweight local monitor server for Linux/desktop.
// Serves a minimal HTML dashboard and exposes REST + WebSocket endpoints
// to inspect the running PeopleChain node.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../sdk/node.dart' as pc;
import '../models/chain_models.dart' as models;
import '../p2p/peer_store.dart' as peers;
import '../../../testing/metrics_bus.dart';
import '../p2p/p2p_manager.dart' as p2p;
import '../utils/memory_info.dart' as mem;

class NodeMonitorServer {
  final pc.PeopleChainNode node;
  HttpServer? _server;
  final _clients = <WebSocket>{};
  Timer? _tick;
  DateTime? _lastTickAt;
  // Throughput buckets accumulated from MetricsBus between ticks
  double _bytesUpBucket = 0;
  double _bytesDownBucket = 0;
  final Set<String> _peersSeen = <String>{};
  final Set<String> _pendingTx = <String>{};

  // Subscriptions for live events
  StreamSubscription? _blockSub;
  StreamSubscription? _txSub;
  StreamSubscription? _peerDiscSub;
  StreamSubscription? _logSub;
  StreamSubscription? _netUpSub;
  StreamSubscription? _netDownSub;

  int port = 8080;
  InternetAddress address = InternetAddress.loopbackIPv4;

  NodeMonitorServer({required this.node});

  // In-memory demo document store for CRUD examples (non-persistent).
  // Structure: { collection: { id: Map<String,dynamic> } }
  final Map<String, Map<String, Map<String, dynamic>>> _docStore = {};
  final Random _rand = Random();

  Future<void> start({String host = '127.0.0.1', int port = 8080}) async {
    if (_server != null) return;
    address = InternetAddress(host);
    this.port = port;

    _server = await HttpServer.bind(address, port, shared: true);
    try {
      // Also emit a console line so users can quickly discover the URL.
      // We avoid heavy dependencies here; MetricsBus logging is handled by the bootstrap.
      // ignore: avoid_print
      print('[Monitor] Bound HTTP server on ${address.address}:$port');
    } catch (_) {}

    _server!.listen((HttpRequest req) async {
      // WebSocket upgrade
      if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
        final socket = await WebSocketTransformer.upgrade(req);
        _handleWs(socket);
        return;
      }

      // REST API
      if (req.uri.path.startsWith('/api/')) {
        // CORS for API consumers and examples
        if (req.method == 'OPTIONS') {
          _applyCors(req.response);
          req.response.statusCode = 204;
          await req.response.close();
          return;
        }
        // Serve static API explorer page
        if (req.uri.path == '/api' || req.uri.path == '/api/' || req.uri.path == '/api/EXPLORER.html') {
          try {
            final file = File('api/EXPLORER.html');
            if (await file.exists()) {
              req.response.headers.contentType = ContentType.html;
              await req.response.addStream(file.openRead());
              await req.response.close();
            } else {
              return _serveString(req, '<h3>/api/EXPLORER.html not found</h3><p>Ensure the repository includes the /api folder.</p>', contentType: ContentType.html);
            }
          } catch (e) {
            req.response.statusCode = 500;
            return _serveString(req, '<pre>Failed to serve API Explorer: ${e.toString()}</pre>', contentType: ContentType.html);
          }
          return;
        }
        await _handleApi(req);
        return;
      }

      // Static: index
      if (req.uri.path == '/' || req.uri.path == '/index.html') {
        return _serveString(req, _INDEX_HTML, contentType: ContentType.html);
      }

      // Fallback 404
      req.response.statusCode = HttpStatus.notFound;
      req.response.write('Not found');
      await req.response.close();
    });

    // Start metrics tick (1s) similar to dashboard heuristics
    _lastTickAt = DateTime.now();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      final now = DateTime.now();
      final expected = _lastTickAt!.add(const Duration(seconds: 1));
      final lagMs = (now.difference(expected).inMilliseconds).clamp(-1000, 1000);
      _lastTickAt = now;
      final load = lagMs <= 0 ? 0.0 : (lagMs / 16.0 * 100.0).clamp(0.0, 100.0);
      _broadcast({
        'type': 'metric',
        'metric': 'cpu',
        'value': load,
        'ts': now.toIso8601String(),
      });
      try {
        final bytes = await mem.getResidentMemoryBytes();
        if (bytes != null) {
          _broadcast({
            'type': 'metric',
            'metric': 'memory_bytes',
            'value': bytes,
            'ts': now.toIso8601String(),
          });
        }
      } catch (_) {}
      // Emit network throughput per second
      final up = _bytesUpBucket.round();
      final down = _bytesDownBucket.round();
      _bytesUpBucket = 0;
      _bytesDownBucket = 0;
      _broadcast({'type': 'metric', 'metric': 'net_up_bps', 'value': up, 'ts': now.toIso8601String()});
      _broadcast({'type': 'metric', 'metric': 'net_down_bps', 'value': down, 'ts': now.toIso8601String()});
      // Emit peer and connection counts
      try {
        final peers = await node.recentPeers(limit: 1000);
        _broadcast({'type': 'metric', 'metric': 'peer_count', 'value': peers.length, 'ts': now.toIso8601String()});
      } catch (_) {}
      _broadcast({'type': 'metric', 'metric': 'active_connections', 'value': node.isTransportOpen ? 1 : 0, 'ts': now.toIso8601String()});
      // Pending tx count
      _broadcast({'type': 'metric', 'metric': 'pending_txs', 'value': _pendingTx.length, 'ts': now.toIso8601String()});
      // Discovery status snapshot (uptime)
      try {
        final d = await node.getDiscoveryStatus();
        _broadcast({'type': 'discovery', 'status': d});
      } catch (_) {}
    });

    // Aggregate network throughput from MetricsBus
    _netUpSub?.cancel();
    _netDownSub?.cancel();
    _netUpSub = MetricsBus.I.netUp().listen((pt) {
      _bytesUpBucket += pt.value;
    });
    _netDownSub = MetricsBus.I.netDown().listen((pt) {
      _bytesDownBucket += pt.value;
    });

    // Live node events
    _blockSub?.cancel();
    _blockSub = node.onBlockAdded().listen((evt) {
      // remove included pending txs
      for (final id in evt.block.txIds) {
        _pendingTx.remove(id);
      }
      _broadcast({'type': 'block', 'block': evt.block.toJson()});
    });
    _txSub?.cancel();
    _txSub = node.onTxReceived().listen((evt) {
      _pendingTx.add(evt.tx.txId);
      _broadcast({'type': 'tx', 'tx': evt.tx.toJson()});
    });
    _peerDiscSub?.cancel();
    _peerDiscSub = node.onPeerDiscovered().listen((p) {
      _peersSeen.add(p.nodeId);
      _broadcast({'type': 'peer', 'peer': _peerInfoToJson(p)});
    });
    _logSub?.cancel();
    _logSub = MetricsBus.I.logs().listen((e) {
      _broadcast({
        'type': 'log',
        'level': e.level.name,
        'ts': e.ts.toIso8601String(),
        'message': e.message,
      });
    });
  }

  Future<void> stop() async {
    _tick?.cancel();
    await _blockSub?.cancel();
    await _txSub?.cancel();
    await _peerDiscSub?.cancel();
    await _logSub?.cancel();
    await _netUpSub?.cancel();
    await _netDownSub?.cancel();
    for (final c in _clients) {
      try { c.close(); } catch (_) {}
    }
    _clients.clear();
    try { await _server?.close(force: true); } catch (_) {}
    _server = null;
  }

  // region: WS/API helpers
  void _handleWs(WebSocket socket) {
    _clients.add(socket);
    socket.listen((data) async {
      // Simple RPCs over WS
      try {
        final msg = jsonDecode(data is String ? data : utf8.decode(data as List<int>)) as Map;
        final type = msg['type'];
        if (type == 'get_info') {
          final info = await node.getNodeInfo();
          final disco = await node.getDiscoveryStatus();
          _send(socket, {'type': 'info', 'node': {
            'node_id': info.nodeId,
            'alias': info.alias,
            'ed25519': info.keys.ed25519,
            'x25519': info.keys.x25519,
            'tip_height': info.tipHeight,
          }, 'discovery': disco});
        }
      } catch (e) {
        _send(socket, {'type': 'error', 'error': e.toString()});
      }
    }, onDone: () {
      _clients.remove(socket);
    }, onError: (_) {
      _clients.remove(socket);
    });
  }

  Future<void> _handleApi(HttpRequest req) async {
    try {
      _applyCors(req.response);
      final p = req.uri.path;
      if (p == '/api/info') {
        final i = await node.getNodeInfo();
        return _json(req, {
          'node_id': i.nodeId,
          'alias': i.alias,
          'ed25519': i.keys.ed25519,
          'x25519': i.keys.x25519,
          'tip_height': i.tipHeight,
        });
      }
      if (p == '/api/discovery') {
        final d = await node.getDiscoveryStatus();
        return _json(req, d.cast<String, dynamic>());
      }
      if (p == '/api/tip') {
        final tip = await node.tipHeight();
        return _json(req, {'tip': tip});
      }
      if (p == '/api/peers') {
        final limit = int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 100;
        final list = await node.recentPeers(limit: limit);
        return _json(req, {'peers': list.map(_peerToJson).toList()});
      }
      if (p == '/api/blocks') {
        final from = req.uri.queryParameters['from'];
        final count = int.tryParse(req.uri.queryParameters['count'] ?? '') ?? 20;
        int start;
        if (from == null || from == 'tip') {
          start = await node.tipHeight();
        } else {
          start = int.tryParse(from) ?? await node.tipHeight();
        }
        final end = (start - count + 1).clamp(0, start);
        final blocks = <models.BlockModel>[];
        for (int h = start; h >= end; h--) {
          final b = await node.getBlockByHeight(h);
          if (b != null) blocks.add(b);
        }
        return _json(req, {'blocks': blocks.map((e) => e.toJson()).toList(), 'next': end - 1});
      }
      if (p.startsWith('/api/block/')) {
        final id = p.substring('/api/block/'.length);
        final b = await node.getBlockById(id);
        return _json(req, {'block': b?.toJson()});
      }
      if (p.startsWith('/api/tx/')) {
        final id = p.substring('/api/tx/'.length);
        final t = await node.getTransactionById(id);
        return _json(req, {'tx': t?.toJson()});
      }
      if (p.startsWith('/api/db/')) {
        return _handleDbApi(req);
      }
      // 404
      req.response.statusCode = HttpStatus.notFound;
      req.response.write('Unknown API');
      await req.response.close();
    } catch (e) {
      req.response.statusCode = 500;
      _json(req, {'error': e.toString()});
    }
  }

  // region: Simple in-memory DB API
  Future<void> _handleDbApi(HttpRequest req) async {
    // Routes:
    //   GET    /api/db/:collection               -> list documents
    //   POST   /api/db/:collection               -> create document (auto id if missing)
    //   GET    /api/db/:collection/:id           -> read document
    //   PUT    /api/db/:collection/:id           -> replace document
    //   PATCH  /api/db/:collection/:id           -> merge update (shallow)
    //   DELETE /api/db/:collection/:id           -> delete document
    final parts = req.uri.path.split('/');
    if (parts.length < 4) {
      req.response.statusCode = HttpStatus.badRequest;
      return _json(req, {'error': 'Collection not specified'});
    }
    final collection = parts[3];
    final col = _docStore.putIfAbsent(collection, () => <String, Map<String, dynamic>>{});

    if (parts.length == 4) {
      // Collection-level ops
      if (req.method == 'GET') {
        final limit = int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 50;
        final offset = int.tryParse(req.uri.queryParameters['offset'] ?? '') ?? 0;
        final q = req.uri.queryParameters['q'];
        final all = col.entries
            .map((e) => {'id': e.key, 'data': e.value})
            .where((e) => q == null || jsonEncode(e['data']).toLowerCase().contains(q.toLowerCase()))
            .toList();
        final slice = all.skip(offset).take(limit).toList();
        return _json(req, {
          'items': slice,
          'total': all.length,
          'limit': limit,
          'offset': offset,
        });
      }
      if (req.method == 'POST') {
        final body = await _readJson(req);
        final providedId = body['id'] as String?;
        final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final id = providedId ?? _genId();
        if (col.containsKey(id)) {
          req.response.statusCode = HttpStatus.conflict;
          return _json(req, {'error': 'Document with id already exists', 'id': id});
        }
        col[id] = data;
        return _json(req, {'ok': true, 'id': id, 'data': data});
      }
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return _json(req, {'error': 'Method not allowed'});
    } else {
      final id = parts[4];
      if (req.method == 'GET') {
        final doc = col[id];
        if (doc == null) {
          req.response.statusCode = HttpStatus.notFound;
          return _json(req, {'error': 'Not found'});
        }
        return _json(req, {'id': id, 'data': doc});
      }
      if (req.method == 'PUT') {
        final body = await _readJson(req);
        final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final created = !col.containsKey(id);
        col[id] = data;
        return _json(req, {'ok': true, 'created': created, 'id': id, 'data': data});
      }
      if (req.method == 'PATCH') {
        final existing = col[id];
        if (existing == null) {
          req.response.statusCode = HttpStatus.notFound;
          return _json(req, {'error': 'Not found'});
        }
        final body = await _readJson(req);
        final patch = (body['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        existing.addAll(patch);
        return _json(req, {'ok': true, 'id': id, 'data': existing});
      }
      if (req.method == 'DELETE') {
        final existed = col.remove(id) != null;
        return _json(req, {'ok': true, 'deleted': existed, 'id': id});
      }
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return _json(req, {'error': 'Method not allowed'});
    }
  }

  String _genId() {
    // Simple base36 timestamp + 3-digit random
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = (_rand.nextInt(1000)).toString().padLeft(3, '0');
    return '${ts}${r}';
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    try {
      final text = await utf8.decoder.bind(req).join();
      if (text.isEmpty) return <String, dynamic>{};
      final v = jsonDecode(text);
      if (v is Map) return v.cast<String, dynamic>();
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _applyCors(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
  }
  // endregion

  void _broadcast(Map<String, dynamic> msg) {
    final data = jsonEncode(msg);
    for (final c in _clients.toList()) {
      try { c.add(data); } catch (_) {}
    }
  }

  void _send(WebSocket socket, Map<String, dynamic> msg) {
    try { socket.add(jsonEncode(msg)); } catch (_) {}
  }

  Future<void> _serveString(HttpRequest req, String body, {ContentType? contentType}) async {
    if (contentType != null) {
      req.response.headers.contentType = contentType;
    }
    req.response.write(body);
    await req.response.close();
  }

  Future<void> _json(HttpRequest req, Map<String, dynamic> map) async {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(map));
    await req.response.close();
  }

  Map<String, dynamic> _peerToJson(peers.PeerRecord p) => {
        'node_id': p.nodeId,
        'alias': p.alias,
        'ed25519': p.ed25519PubKey,
        'x25519': p.x25519PubKey,
        'last_seen_ms': p.lastSeenMs,
        'transports': p.transports,
      };

  Map<String, dynamic> _peerInfoToJson(p2p.PeerInfo p) => {
        'node_id': p.nodeId,
        'alias': p.alias,
        'ed25519': p.ed25519PubKey,
        'x25519': p.x25519PubKey,
        'transports': p.transports,
        // last_seen_ms not available directly; use now
        'last_seen_ms': DateTime.now().millisecondsSinceEpoch,
      };
}

const String _INDEX_HTML = r"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>PeopleChain • Node Monitor</title>
    <style>
      :root { color-scheme: light dark; }
      body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, 'Helvetica Neue', Arial, 'Noto Sans', 'Apple Color Emoji', 'Segoe UI Emoji';
             margin: 0; padding: 0; background: #0b0d10; color: #e8eaed; }
      header { display:flex; align-items:center; justify-content:space-between; padding:12px 16px; background: #111419; position: sticky; top:0; z-index: 10; }
      header h1 { font-size: 16px; margin: 0; font-weight: 600; }
      header .addr { opacity: .7; font-size: 12px; }
      .tabs { display:flex; gap:8px; padding: 8px 12px; border-bottom: 1px solid rgba(255,255,255,.08); overflow:auto; }
      .tab { padding: 8px 12px; background:#171b22; border-radius: 18px; cursor: pointer; white-space: nowrap; }
      .tab.active { background:#2556d0; color: white; }
      main { padding: 12px; }
      .grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap:12px; }
      .card { background:#111419; border:1px solid rgba(255,255,255,.06); border-radius: 12px; padding: 12px; }
      .row { display:flex; align-items:center; gap:8px; }
      .muted { opacity:.7; font-size:12px; }
      code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 12px; }
      table { border-collapse: collapse; width: 100%; }
      td, th { text-align: left; padding: 6px 8px; border-bottom: 1px solid rgba(255,255,255,.06); }
      .pill { padding:2px 8px; background:#1b2130; border-radius: 999px; font-size: 12px; }
      .list { display: grid; gap: 8px; }
      .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
      .right { text-align: right; }
      .logs { height: 40vh; overflow: auto; background:#0f1217; border-radius:8px; padding:8px; }
    </style>
  </head>
  <body>
    <header>
      <h1>PeopleChain • Node Monitor <span class="addr" id="hdr"></span></h1>
      <div><span class="pill" id="sync">connecting</span></div>
    </header>
    <div class="tabs">
      <div class="tab active" data-tab="overview">Overview</div>
      <div class="tab" data-tab="tests">Interactive Tests</div>
      <div class="tab" data-tab="network">Network Metrics</div>
      <div class="tab" data-tab="logs">Logs & Telemetry</div>
      <div class="tab" data-tab="peers">Peers</div>
      <div class="tab" data-tab="chain">Chain</div>
      <div class="tab" data-tab="api">API</div>
      <div class="tab" data-tab="explorer">Explorer</div>
    </div>
    <main>
      <section id="overview">
        <div class="grid">
          <div class="card"><div class="muted">CPU (heuristic)</div><div id="cpu" style="font-size:22px">–%</div><canvas id="chart_cpu" width="300" height="60"></canvas></div>
          <div class="card"><div class="muted">Memory</div><div id="mem" style="font-size:22px">–</div><canvas id="chart_mem" width="300" height="60"></canvas></div>
          <div class="card"><div class="muted">Net Up</div><div id="net_up" style="font-size:22px">–/s</div><canvas id="chart_up" width="300" height="60"></canvas></div>
          <div class="card"><div class="muted">Net Down</div><div id="net_down" style="font-size:22px">–/s</div><canvas id="chart_down" width="300" height="60"></canvas></div>
          <div class="card"><div class="muted">Peers</div><div id="peers" style="font-size:22px">–</div></div>
          <div class="card"><div class="muted">Active Connections</div><div id="conns" style="font-size:22px">–</div></div>
          <div class="card"><div class="muted">Pending TXs</div><div id="pending" style="font-size:22px">–</div></div>
          <div class="card"><div class="muted">Tip Height</div><div id="tip" style="font-size:22px">–</div></div>
          <div class="card"><div class="muted">Discovery Relay</div><div id="disco" class="mono" style="font-size:12px; line-height:1.5"></div></div>
          <div class="card"><div class="muted">Node</div><div id="node" class="mono"></div></div>
        </div>
      </section>
      <section id="tests" style="display:none">
        <div class="card">This lightweight monitor exposes the same node APIs. Tests can be triggered via REST shortly.</div>
      </section>
      <section id="network" style="display:none">
        <div class="grid">
          <div class="card"><div class="muted">Connection Stability</div><div id="stab">–</div></div>
          <div class="card"><div class="muted">RTT (ms)</div><div id="rtt">–</div></div>
          <div class="card"><div class="muted">ICE Setup (ms)</div><div id="ice">–</div></div>
          <div class="card"><div class="muted">Connection Time (ms)</div><div id="conn">–</div></div>
        </div>
      </section>
      <section id="logs" style="display:none">
        <div class="card">
          <div class="logs" id="logsBox"></div>
        </div>
      </section>
      <section id="peers" style="display:none">
        <div class="card">
          <table id="peerTable"><thead><tr><th>Alias</th><th>Node</th><th class="right">Last Seen</th></tr></thead><tbody></tbody></table>
        </div>
      </section>
      <section id="chain" style="display:none">
        <div class="list" id="recentBlocks"></div>
      </section>
      <section id="api" style="display:none">
        <div class="card">
          <div class="muted">Try: <code>GET /api/info</code>, <code>/api/peers</code>, <code>/api/blocks</code></div>
          <div style="margin-top:8px;">
            <a href="/api/EXPLORER.html" target="_blank" style="display:inline-block; padding:8px 12px; background:#2556d0; color:white; border-radius:999px; text-decoration:none;">Open API Explorer ↗</a>
          </div>
        </div>
      </section>
      <section id="explorer" style="display:none">
        <div class="card">
          <input id="search" placeholder="Block height / block id / tx id" style="width:60%"/>
          <button onclick="doSearch()">Search</button>
          <div id="searchOut" class="mono"></div>
        </div>
      </section>
    </main>
    <script>
      const tabs = document.querySelectorAll('.tab');
      tabs.forEach(t => t.addEventListener('click', () => {
        tabs.forEach(x => x.classList.remove('active'));
        t.classList.add('active');
        document.querySelectorAll('main section').forEach(s => s.style.display = 'none');
        document.getElementById(t.dataset.tab).style.display = 'block';
      }));

      const ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws');
      ws.addEventListener('open', () => ws.send(JSON.stringify({type:'get_info'})));
      const series = { cpu: [], mem: [], up: [], down: [] };
      let memMax = 1;
      let upMax = 1, downMax = 1;
      function push(arr, v) { arr.push(v); if (arr.length > 60) arr.shift(); }
      function draw(id, arr, color, maxVal) {
        const c = document.getElementById(id); if (!c) return; const ctx = c.getContext('2d'); const w=c.width, h=c.height; ctx.clearRect(0,0,w,h);
        if (arr.length < 2) return; const maxv = maxVal || Math.max(1, ...arr);
        ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.beginPath();
        for (let i=0;i<arr.length;i++){ const x=i*(w/(arr.length-1)); const y=h - (arr[i]/maxv)*h; if(i===0) ctx.moveTo(x,y); else ctx.lineTo(x,y);} ctx.stroke();
      }
      function hb(n) { if (n<1024) return n+' B'; const i=Math.floor(Math.log(n)/Math.log(1024)); return (n/Math.pow(1024,i)).toFixed(1)*1+' '+['B','KB','MB','GB','TB'][i]; }

      ws.addEventListener('message', (e) => {
        const msg = JSON.parse(e.data);
        if (msg.type === 'metric') {
          if (msg.metric === 'cpu') { document.getElementById('cpu').textContent = msg.value.toFixed(1) + '%'; push(series.cpu, msg.value); draw('chart_cpu', series.cpu, '#4e8cff'); }
          if (msg.metric === 'memory_bytes') { document.getElementById('mem').textContent = humanBytes(msg.value); memMax = Math.max(memMax, msg.value); push(series.mem, msg.value); draw('chart_mem', series.mem, '#7dd56f', memMax); }
          if (msg.metric === 'net_up_bps') { document.getElementById('net_up').textContent = hb(msg.value) + '/s'; upMax = Math.max(upMax, msg.value); push(series.up, msg.value); draw('chart_up', series.up, '#ffd166', upMax); }
          if (msg.metric === 'net_down_bps') { document.getElementById('net_down').textContent = hb(msg.value) + '/s'; downMax = Math.max(downMax, msg.value); push(series.down, msg.value); draw('chart_down', series.down, '#ef476f', downMax); }
          if (msg.metric === 'peer_count') { document.getElementById('peers').textContent = msg.value; }
          if (msg.metric === 'active_connections') { document.getElementById('conns').textContent = msg.value; }
          if (msg.metric === 'pending_txs') { document.getElementById('pending').textContent = msg.value; }
        } else if (msg.type === 'info') {
          const n = msg.node; document.getElementById('hdr').textContent = ' • ' + n.node_id.slice(0,10) + '…';
          document.getElementById('node').textContent = JSON.stringify(n, null, 2);
          document.getElementById('tip').textContent = n.tip_height;
          if (msg.discovery) { renderDisco(msg.discovery); }
        } else if (msg.type === 'log') {
          const box = document.getElementById('logsBox');
          const line = `[${msg.ts}] ${msg.level.toUpperCase()}  ${msg.message}`;
          const p = document.createElement('div'); p.textContent = line; box.appendChild(p); box.scrollTop = box.scrollHeight;
        } else if (msg.type === 'peer') {
          addPeer(msg.peer);
        } else if (msg.type === 'block') {
          addBlock(msg.block);
          // bump tip if present
          document.getElementById('tip').textContent = msg.block.header.height;
        } else if (msg.type === 'discovery') {
          renderDisco(msg.status);
        }
      });

      function humanBytes(n) { const i = Math.floor(Math.log(n)/Math.log(1024)); return (n/Math.pow(1024,i)).toFixed(1)*1 + ' ' + ['B','KB','MB','GB','TB'][i]; }
      function renderDisco(d) {
        if (!d) return;
        const run = d.running ? 'running' : 'stopped';
        const up = d.uptime_s != null ? d.uptime_s + 's' : '–';
        const addr = (d.host || '127.0.0.1') + ':' + (d.port || 8081);
        document.getElementById('disco').textContent = `${run} at http://${addr}\nup: ${up}`;
      }

      async function refreshPeers() {
        const res = await fetch('/api/peers'); const j = await res.json(); const tbody = document.querySelector('#peerTable tbody'); tbody.innerHTML = '';
        j.peers.forEach(addPeer);
      }
      function addPeer(p) {
        const tbody = document.querySelector('#peerTable tbody');
        const tr = document.createElement('tr');
        const alias = document.createElement('td'); alias.textContent = p.alias || '—';
        const node = document.createElement('td'); node.textContent = p.node_id.slice(0, 10) + '…'; node.className='mono';
        const last = document.createElement('td'); last.textContent = new Date(p.last_seen_ms).toISOString(); last.className='right';
        tr.appendChild(alias); tr.appendChild(node); tr.appendChild(last); tbody.prepend(tr);
      }

      async function refreshBlocks() {
        const res = await fetch('/api/blocks?from=tip&count=20'); const j = await res.json();
        const list = document.getElementById('recentBlocks'); list.innerHTML = '';
        j.blocks.forEach(addBlock);
      }
      function addBlock(b) {
        const el = document.createElement('div'); el.className='card';
        el.innerHTML = `<div class="row"><div>#${b.header.height}</div><div class="muted mono">${b.header.block_id.slice(0,12)}…</div><div class="muted">${new Date(b.header.timestamp_ms).toISOString()}</div><div class="pill">tx: ${b.tx_ids.length}</div></div>`;
        document.getElementById('recentBlocks').prepend(el);
      }

      async function doSearch() {
        const q = document.getElementById('search').value.trim(); if (!q) return;
        let out = '';
        const h = parseInt(q, 10); if (!isNaN(h)) { out = JSON.stringify(await (await fetch('/api/blocks?from='+h+'&count=1')).json(), null, 2); }
        else {
          const b = await (await fetch('/api/block/'+q)).json(); if (b.block) out = JSON.stringify(b, null, 2);
          else { const t = await (await fetch('/api/tx/'+q)).json(); if (t.tx) out = JSON.stringify(t, null, 2); else out = 'Not found'; }
        }
        document.getElementById('searchOut').textContent = out;
      }

      // initial data
      refreshPeers(); refreshBlocks();
    </script>
  </body>
</html>
""";
