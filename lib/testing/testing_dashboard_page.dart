import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'metrics_bus.dart';
import 'test_harness.dart';
import 'web_test_mode.dart';
import '../peoplechain_core/peoplechain_core.dart' as pc;
import '../peoplechain_core/src/utils/memory_info.dart' as mem;
import 'js_bridge.dart';
// Platform-specific monitor WebSocket client (web only)
import 'monitor_ws_stub.dart' if (dart.library.html) 'monitor_ws_web.dart' as mon;

class TestingDashboardPage extends StatefulWidget {
  final pc.PeopleChainNode? node;
  const TestingDashboardPage({super.key, this.node});

  @override
  State<TestingDashboardPage> createState() => _TestingDashboardPageState();
}

class _TestingDashboardPageState extends State<TestingDashboardPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  // Maintain a capped, in-place updated list of points per metric for smooth rebuilds
  final List<FlSpot> _latency = <FlSpot>[];
  final List<FlSpot> _handshake = <FlSpot>[];
  final List<FlSpot> _cpu = <FlSpot>[];
  final List<FlSpot> _mem = <FlSpot>[];
  final List<FlSpot> _stab = <FlSpot>[];
  final List<FlSpot> _rtt = <FlSpot>[];
  final List<FlSpot> _ice = <FlSpot>[];
  final List<FlSpot> _conn = <FlSpot>[];
  final List<LogEntry> _logs = [];
  StreamSubscription? _logSub;
  StreamSubscription? _latSub;
  StreamSubscription? _hsSub;
  StreamSubscription? _cpuSub;
  StreamSubscription? _memSub;
  StreamSubscription? _stabSub;
  StreamSubscription? _rttSub;
  StreamSubscription? _iceSub;
  StreamSubscription? _connSub;
  Timer? _perfTimer;
  Timer? _rttTimer;
  double _cpuSmoothed = 0;
  DateTime? _lastTickAt;

  // Memory Guard: compare local app memory vs remote node memory
  int? _localMemBytes;
  int? _nodeMemBytes;
  double? get _memRatio => (_localMemBytes != null && _nodeMemBytes != null && _nodeMemBytes! > 0)
      ? _localMemBytes! / _nodeMemBytes!
      : null;
  final TextEditingController _monitorUrlCtrl = TextEditingController(text: 'ws://127.0.0.1:8080/ws');
  dynamic _monitorClient; // late-bound monitor ws client (web only)
  StreamSubscription? _monitorStatusTicker; // emits periodic guard checks

  // A PeopleChain node to back the dashboard. If none injected, we create one locally.
  pc.PeopleChainNode? _node;
  bool _nodeStarted = false;

  // Peers panel state
  List<pc.PeerRecord> _peers = const [];
  StreamSubscription? _peerDiscSub;

  // Chain panel state
  int _tip = -1;
  List<pc.BlockModel> _recentBlocks = const [];
  StreamSubscription? _blockSub;
  // Live TX stream for "data sent between peers"
  final List<pc.TxModel> _liveTxs = <pc.TxModel>[];
  StreamSubscription? _txSub;
  String? _selfEd25519;

  // API panel state
  bool _apiExposed = false;
  String? _apiLastResponse;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
    registerDefaultSuites();
    _subscribe();
    _ensureNode();
    _startSystemMonitors();
  }

  void _subscribe() {
    _logSub = MetricsBus.I.logs().listen((e) {
      setState(() => _logs.add(e));
    });
    void addPoint(List<FlSpot> tgt, MetricsPoint p) {
      // Avoid excessive rebuilds; cap to last 300 points
      const cap = 300;
      final x = p.ts.millisecondsSinceEpoch.toDouble();
      // mutate in place, then setState once for the series
      tgt.add(FlSpot(x, p.value));
      if (tgt.length > cap) {
        tgt.removeRange(0, tgt.length - cap);
      }
      setState(() {});
    }
    _latSub = MetricsBus.I.latency().listen((p) => addPoint(_latency, p));
    _hsSub = MetricsBus.I.handshake().listen((p) => addPoint(_handshake, p));
    _cpuSub = MetricsBus.I.cpu().listen((p) => addPoint(_cpu, p));
    _memSub = MetricsBus.I.memory().listen((p) => addPoint(_mem, p));
    _stabSub = MetricsBus.I.stability().listen((p) => addPoint(_stab, p));
    _rttSub = MetricsBus.I.handshakeRtt().listen((p) => addPoint(_rtt, p));
    _iceSub = MetricsBus.I.iceSetup().listen((p) => addPoint(_ice, p));
    _connSub = MetricsBus.I.connectionTime().listen((p) => addPoint(_conn, p));
  }

  Future<void> _ensureNode() async {
    if (widget.node != null) {
      // Reuse the app's running node so peers and chain reflect the active session
      final node = widget.node!;
      setState(() {
        _node = node;
        _nodeStarted = true;
      });
      _peerDiscSub?.cancel();
      _peerDiscSub = node.onPeerDiscovered().listen((_) => _refreshPeers());
      _blockSub?.cancel();
      _blockSub = node.onBlockAdded().listen((_) {
        _refreshChain();
        _onExplorerNewBlock();
      });
      _txSub?.cancel();
      _txSub = node.onTxReceived().listen((e) => _onTx(e.tx));
      // Cache our own ed25519 for nicer labeling
      unawaited(node.getNodeInfo().then((i) => setState(() => _selfEd25519 = i.keys.ed25519)));
      unawaited(_refreshPeers());
      unawaited(_refreshChain());
    } else {
      // Create a dedicated node for the dashboard (web: in-memory DB)
      final node = pc.PeopleChainNode();
      await node.startNodeWithProgress(pc.NodeConfig(alias: 'WebTest', useIsarDb: !kIsWeb));
      setState(() {
        _node = node;
        _nodeStarted = true;
      });
      _peerDiscSub?.cancel();
      _peerDiscSub = node.onPeerDiscovered().listen((_) => _refreshPeers());
      _blockSub?.cancel();
      _blockSub = node.onBlockAdded().listen((_) {
        _refreshChain();
        _onExplorerNewBlock();
      });
      _txSub?.cancel();
      _txSub = node.onTxReceived().listen((e) => _onTx(e.tx));
      unawaited(node.getNodeInfo().then((i) => setState(() => _selfEd25519 = i.keys.ed25519)));
      unawaited(_refreshPeers());
      unawaited(_refreshChain());
    }
  }

  void _startSystemMonitors() {
    // 1s tick: estimate CPU from event loop lag, measure memory, and stability
    _lastTickAt = DateTime.now();
    _perfTimer?.cancel();
    _perfTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final now = DateTime.now();
      final expected = _lastTickAt!.add(const Duration(seconds: 1));
      final lagMs = (now.difference(expected).inMilliseconds).clamp(-1000, 1000);
      _lastTickAt = now;
      // Map scheduler lag to a 0-100 CPU-ish load (heuristic)
      final load = (lagMs <= 0) ? 0.0 : (lagMs / 16.0 * 100.0).clamp(0.0, 100.0);
      _cpuSmoothed = _cpuSmoothed * 0.7 + load * 0.3;
      MetricsBus.I.recordCpu(_cpuSmoothed);

      // Memory
      try {
        // Prefer platform-provided memory; web returns JS heap bytes
        final bytes = await mem.getResidentMemoryBytes();
        if (bytes != null) {
          _localMemBytes = bytes;
          MetricsBus.I.recordMemoryBytes(bytes);
        }
      } catch (_) {
        // Swallow
      }

      // Stability: 1 when transport open, 0 otherwise, smoothed by moving average
      final open = (_node?.isTransportOpen ?? false) ? 1.0 : 0.0;
      MetricsBus.I.recordStability(open);
    });

    // 2s tick: measure RTT when link available
    _rttTimer?.cancel();
    _rttTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_node?.isTransportOpen ?? false) {
        try {
          final rtt = await _node!.measureTransportRtt();
          if (rtt != null) MetricsBus.I.recordLatency(rtt);
        } catch (_) {}
      }
    });

    // Opportunistic peer/chain refresh on small screens where users jump between tabs.
    // Also recovers if a discovery event was missed while the page was inactive.
    _peerAutoRefresh?.cancel();
    _peerAutoRefresh = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _node == null) return;
      // Cheap polling; PeerStore is in-memory on web.
      unawaited(_refreshPeers());
      // Keep chain summary warm for the chips/timeline.
      unawaited(_refreshChain());
    });

    // MemoryGuard: periodic status check (2s) — warn if we exceed 25% of node memory
    _monitorStatusTicker?.cancel();
    _monitorStatusTicker = Stream.periodic(const Duration(seconds: 2)).listen((_) {
      final r = _memRatio;
      if (r != null) {
        if (r > 0.25) {
          MetricsBus.I.logWarn('MemoryGuard: app uses ${(r * 100).toStringAsFixed(1)}% of node memory (>25%)');
        }
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _logSub?.cancel();
    _latSub?.cancel();
    _hsSub?.cancel();
    _cpuSub?.cancel();
    _memSub?.cancel();
    _stabSub?.cancel();
    _rttSub?.cancel();
    _iceSub?.cancel();
    _connSub?.cancel();
    _perfTimer?.cancel();
    _rttTimer?.cancel();
    _peerDiscSub?.cancel();
    _blockSub?.cancel();
    _txSub?.cancel();
    _peerAutoRefresh?.cancel();
    try { (_monitorClient as dynamic)?.close(); } catch (_) {}
    _monitorStatusTicker?.cancel();
    _blocksScroll.removeListener(_onBlocksScroll);
    _txsScroll.removeListener(_onTxsScroll);
    _blocksScroll.dispose();
    _txsScroll.dispose();
    _explorerSearchCtrl.dispose();
    try {
      unregisterJsApi();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compactTabs = width < 420;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Testing Dashboard'),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: () {
              WebTestMode.deactivate();
              if (mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.power_settings_new, color: Colors.red),
            label: const Text('Deactivate Web Test Mode'),
          )
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(icon: const Icon(Icons.dashboard), text: compactTabs ? 'Overview' : 'Overview'),
            Tab(icon: const Icon(Icons.bug_report), text: compactTabs ? 'Tests' : 'Interactive Tests'),
            Tab(icon: const Icon(Icons.network_check), text: compactTabs ? 'Network' : 'Network Metrics'),
            Tab(icon: const Icon(Icons.notes), text: compactTabs ? 'Logs' : 'Logs & Telemetry'),
            Tab(icon: const Icon(Icons.people_alt), text: 'Peers'),
            Tab(icon: const Icon(Icons.account_tree), text: 'Chain'),
            Tab(icon: const Icon(Icons.api), text: 'API'),
            Tab(icon: const Icon(Icons.explore), text: 'Explorer'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _overview(),
          _interactiveTests(),
          _networkMetrics(),
          _logsView(),
          _peersView(),
          _chainView(),
          _apiView(),
          _explorerView(),
        ],
      ),
    );
  }

  Widget _overview() {
    return LayoutBuilder(builder: (context, c) {
      final isWide = c.maxWidth > 840;
      return Padding(
        padding: const EdgeInsets.all(12),
        child: isWide
            ? Row(children: [
                Expanded(child: _chartCard('Message Latency (ms)', _latency)),
                const SizedBox(width: 12),
                Expanded(child: _chartCard('Handshake Duration (ms)', _handshake)),
              ])
            : ListView(children: [
                _chartCard('Message Latency (ms)', _latency),
                const SizedBox(height: 12),
                _chartCard('Handshake Duration (ms)', _handshake),
              ]),
      );
    });
  }

  Widget _interactiveTests() {
    final tests = TestHarness.I.tests;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView.separated(
        itemCount: tests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _testCard(tests[i]),
      ),
    );
  }

  Widget _networkMetrics() {
    return LayoutBuilder(builder: (context, c) {
      final isWide = c.maxWidth >= 840;
      final child = Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Memory Guard control & status row
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.memory, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Memory Guard', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _connectMonitor,
                      icon: const Icon(Icons.link, color: Colors.blue),
                      label: const Text('Connect Monitor'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _monitorUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Monitor WS URL (ws://host:port/ws)',
                          prefixIcon: Icon(Icons.router, color: Colors.blue),
                        ),
                        onSubmitted: (_) => _connectMonitor(),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Chip(label: Text('App: ${_humanBytes(_localMemBytes)}')),
                    Chip(label: Text('Node: ${_humanBytes(_nodeMemBytes)}')),
                    Builder(builder: (_) {
                      final r = _memRatio;
                      Color color = Theme.of(context).colorScheme.onSurface;
                      String text = 'Ratio: –';
                      if (r != null) {
                        text = 'Ratio: ${(r * 100).toStringAsFixed(1)}%';
                        if (r <= 0.25) color = Colors.green;
                        else if (r <= 0.4) color = Colors.orange;
                        else color = Theme.of(context).colorScheme.error;
                      }
                      return Chip(label: Text(text, style: TextStyle(color: color)));
                    }),
                  ])
                ],
              ),
            ),
            const SizedBox(height: 12),
            isWide
                ? Row(children: [
                    Expanded(child: _chartCard('CPU (%)', _cpu)),
                    const SizedBox(width: 12),
                    Expanded(child: _chartCard('Memory (bytes)', _mem)),
                  ])
                : Column(children: [
                    _chartCard('CPU (%)', _cpu),
                    const SizedBox(height: 12),
                    _chartCard('Memory (bytes)', _mem),
                  ]),
            const SizedBox(height: 12),
            _chartCard('Connection Stability', _stab),
            const SizedBox(height: 12),
            isWide
                ? Row(children: [
                    Expanded(child: _chartCard('RTT (ms)', _rtt)),
                    const SizedBox(width: 12),
                    Expanded(child: _chartCard('ICE Setup (ms)', _ice)),
                  ])
                : Column(children: [
                    _chartCard('RTT (ms)', _rtt),
                    const SizedBox(height: 12),
                    _chartCard('ICE Setup (ms)', _ice),
                  ]),
            const SizedBox(height: 12),
            _chartCard('Connection Time (ms)', _conn),
            const SizedBox(height: 12),
            _webrtcQuickActions(),
          ],
        ),
      );
      return child;
    });
  }

  Widget _logsView() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (context, i) {
            final e = _logs[i];
            Color c = Theme.of(context).colorScheme.onSurface;
            if (e.level == LogLevel.warning) c = Colors.orange;
            if (e.level == LogLevel.error) c = Theme.of(context).colorScheme.error;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Text(e.ts.toIso8601String(), style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.message, style: TextStyle(color: c))),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _humanBytes(int? n) {
    if (n == null) return '–';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double d = n.toDouble();
    while (d >= 1024 && i < units.length - 1) { d /= 1024; i++; }
    return '${d.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  void _connectMonitor() {
    // Web-only: use a lightweight html.WebSocket bridge. On non-web, no-op with a hint log.
    const isWeb = kIsWeb;
    if (!isWeb) {
      MetricsBus.I.logWarn('MemoryGuard: Monitor connect is only available on Web preview.');
      return;
    }
    try {
      // Dispose previous
      try { (_monitorClient as dynamic)?.close(); } catch (_) {}
    } catch (_) {}

    final url = _monitorUrlCtrl.text.trim();
    if (url.isEmpty) return;
    _monitorClient = mon.WebMonitorClient(
      url: url,
      onMemoryBytes: (int bytes) {
        setState(() { _nodeMemBytes = bytes; });
      },
      onError: (e) {
        MetricsBus.I.logWarn('MemoryGuard: monitor error: $e');
      },
    )..connect();
  }

  Widget _chartCard(String title, List<FlSpot> series) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assessment, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => series.clear()),
                icon: const Icon(Icons.clear, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RepaintBoundary(
            child: SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      dotData: const FlDotData(show: false),
                      spots: series,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _testCard(TestCaseDef def) {
    return _Card(
      child: _TestCardContent(def: def),
    );
  }

  Widget _webrtcQuickActions() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('WebRTC Quick Actions', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (!_nodeStarted)
            const Text('Starting local peer node...')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: const StadiumBorder(),
                    splashFactory: NoSplash.splashFactory,
                  ),
                  onPressed: () async {
                    final payload = await _node!.createOfferPayload();
                    MetricsBus.I.logInfo('Offer created. Share with peer.');
                    await _showTextDialog('Offer (copy to peer)', payload);
                  },
                  icon: const Icon(Icons.upload),
                  label: const Text('Create Offer'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final text = await _prompt('Paste Offer text');
                    if (text == null || text.trim().isEmpty) return;
                    final sw = Stopwatch()..start();
                    final ans = await _node!.acceptOfferAndCreateAnswer(text.trim());
                    try {
                      await _node!.onTransportOpen().first.timeout(const Duration(seconds: 10));
                      sw.stop();
                      MetricsBus.I.recordIceSetup(sw.elapsed);
                      MetricsBus.I.recordConnectionTime(sw.elapsed);
                      final rtt = await _node!.measureTransportRtt();
                      if (rtt != null) MetricsBus.I.recordHandshakeRtt(rtt);
                    } catch (_) {}
                    await _showTextDialog('Answer (send back to peer)', ans);
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Accept Offer'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final text = await _prompt('Paste Answer text');
                    if (text == null || text.trim().isEmpty) return;
                    final sw = Stopwatch()..start();
                    try {
                      await _node!.acceptAnswer(text.trim());
                    } catch (e) {
                      final msg = e.toString();
                      if (!(msg.contains('Called in wrong state') || msg.contains('stable') || msg.contains('InvalidStateError'))) {
                        MetricsBus.I.logError('Accept Answer failed: $e');
                        return;
                      }
                    }
                    try {
                      if (!_node!.isTransportOpen) {
                        await _node!.onTransportOpen().first.timeout(const Duration(seconds: 10));
                      }
                      sw.stop();
                      MetricsBus.I.recordIceSetup(sw.elapsed);
                      MetricsBus.I.recordConnectionTime(sw.elapsed);
                      final rtt = await _node!.measureTransportRtt();
                      if (rtt != null) MetricsBus.I.recordHandshakeRtt(rtt);
                    } catch (e) {
                      MetricsBus.I.logWarn('Timed out waiting for data channel open: $e');
                    }
                    MetricsBus.I.logInfo('Answer accepted. Data channel should open (or is already open).');
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Accept Answer'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // region: Peers
  Future<void> _refreshPeers() async {
    if (_node == null) return;
    final list = await _node!.recentPeers(limit: 100);
    setState(() => _peers = list);
  }

  String _ago(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Widget _peersView() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.people_alt, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Recent Peers', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _refreshPeers,
              icon: const Icon(Icons.refresh, color: Colors.blue),
              label: const Text('Refresh'),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: _peers.isEmpty
                ? const Center(child: Text('No peers discovered yet. Perform a handshake or discovery.'))
                : ListView.separated(
                    itemCount: _peers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = _peers[i];
                      return _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(p.alias ?? p.nodeId, style: Theme.of(context).textTheme.titleMedium)),
                              Text(_ago(p.lastSeenMs), style: Theme.of(context).textTheme.labelSmall),
                            ]),
                            const SizedBox(height: 6),
                            SelectableText('ed25519: ${p.ed25519PubKey}'),
                            SelectableText('x25519: ${p.x25519PubKey}'),
                            const SizedBox(height: 6),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              Chip(label: Text('Transports: ${p.transports.join(', ')}')),
                              OutlinedButton.icon(
                                onPressed: (_node?.isTransportOpen ?? false)
                                    ? () async {
                                        try {
                                          final r = await _node!.sendMessage(toPubKey: p.ed25519PubKey, text: 'hello 👋');
                                          if (!r.ok) {
                                            MetricsBus.I.logWarn('Send hello failed: ${r.error}');
                                          } else {
                                            MetricsBus.I.logInfo('Sent hello to ${p.alias ?? p.nodeId}: ${r.txId}');
                                          }
                                        } catch (e) {
                                          MetricsBus.I.logError('Send hello error: $e');
                                        }
                                      }
                                    : null,
                                icon: const Icon(Icons.send, color: Colors.blue),
                                label: const Text('Send hello'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: p.ed25519PubKey));
                                  MetricsBus.I.logInfo('Copied ed25519 to clipboard');
                                },
                                icon: const Icon(Icons.copy, color: Colors.blue),
                                label: const Text('Copy ed25519'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _showPeerDetails(p),
                                icon: const Icon(Icons.info, color: Colors.blue),
                                label: const Text('Details'),
                              ),
                            ])
                          ],
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
  // endregion

  // region: Chain
  Future<void> _refreshChain() async {
    if (_node == null) return;
    final tip = await _node!.tipHeight();
    final blocks = <pc.BlockModel>[];
    for (int h = tip; h >= 0 && blocks.length < 20; h--) {
      final b = await _node!.getBlockByHeight(h);
      if (b != null) blocks.add(b);
    }
    setState(() {
      _tip = tip;
      _recentBlocks = blocks;
    });
  }

  void _onTx(pc.TxModel tx) {
    // Maintain a capped, newest-first list
    const cap = 100;
    _liveTxs.insert(0, tx);
    if (_liveTxs.length > cap) {
      _liveTxs.removeRange(cap, _liveTxs.length);
    }
    setState(() {});
  }

  int get _txLastMinuteCount {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _liveTxs.where((t) => (now - t.timestampMs) <= 60000).length;
  }

  Widget _chainView() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.account_tree, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Chain Overview', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _refreshChain,
              icon: const Icon(Icons.refresh, color: Colors.blue),
              label: const Text('Refresh'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _showChainDetails,
              icon: const Icon(Icons.insights, color: Colors.blue),
              label: const Text('Details'),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(label: Text('Tip: $_tip')),
            Chip(label: Text('Live TX (1m): ${_txLastMinuteCount}')),
            Chip(label: Text('Recent blocks: ${_recentBlocks.length}')),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: _recentBlocks.isEmpty && _liveTxs.isEmpty
                ? const Center(child: Text('No blocks or messages yet. Try sending a message.'))
                : ListView(
                    children: [
                      // Horizontal block timeline visualization
                      if (_recentBlocks.isNotEmpty) ...[
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.timeline, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('Recent Blocks Timeline', style: Theme.of(context).textTheme.titleSmall),
                              ]),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 128,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _recentBlocks.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                                  itemBuilder: (context, i) => _blockViz(_recentBlocks[i]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Live transactions feed (data sent between peers)
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.send_and_archive, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Live Transactions', style: Theme.of(context).textTheme.titleSmall)),
                              Text('${_liveTxs.length} shown', style: Theme.of(context).textTheme.labelSmall),
                            ]),
                            const SizedBox(height: 8),
                            if (_liveTxs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(child: Text('No transactions yet')),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _liveTxs.length.clamp(0, 30),
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, i) => _txRow(_liveTxs[i]),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Recent blocks list
                      if (_recentBlocks.isNotEmpty)
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.inventory_2, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('Recent Blocks', style: Theme.of(context).textTheme.titleSmall),
                              ]),
                              const SizedBox(height: 8),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _recentBlocks.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final b = _recentBlocks[i];
                                  return _Card(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Icon(Icons.view_in_ar, color: Theme.of(context).colorScheme.primary),
                                          const SizedBox(width: 8),
                                          Text('#${b.header.height}', style: Theme.of(context).textTheme.titleMedium),
                                          const Spacer(),
                                          Text(
                                            DateTime.fromMillisecondsSinceEpoch(b.header.timestampMs).toIso8601String(),
                                            style: Theme.of(context).textTheme.labelSmall,
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed: () => _showBlockDetails(b),
                                            icon: const Icon(Icons.info, color: Colors.blue),
                                            label: const Text('Details'),
                                          ),
                                        ]),
                                        const SizedBox(height: 6),
                                        SelectableText('blockId: ${b.header.blockId}'),
                                        SelectableText('prev: ${b.header.prevBlockId}'),
                                        Text('tx count: ${b.txIds.length}', style: Theme.of(context).textTheme.bodySmall),
                                        if (b.signatures.isNotEmpty)
                                          Text('signatures: ${b.signatures.length}', style: Theme.of(context).textTheme.bodySmall),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          )
        ],
      ),
    );
  }
  // endregion

  // region: Explorer (Blocks & Transactions like Etherscan)
  final TextEditingController _explorerSearchCtrl = TextEditingController();
  int _explorerTip = -1;
  Timer? _peerAutoRefresh;
  // Blocks paging
  final List<pc.BlockModel> _explorerBlocks = <pc.BlockModel>[];
  bool _loadingBlocks = false;
  int _nextBlockHeightToLoad = -1; // inclusive, descending
  // TX paging derived from blocks
  final List<pc.TxModel> _explorerTxs = <pc.TxModel>[];
  bool _loadingTxs = false;
  int _scanHeightForTx = -1; // descending scan pointer
  final ScrollController _blocksScroll = ScrollController();
  final ScrollController _txsScroll = ScrollController();

  Future<void> _initExplorer() async {
    if (_node == null) return;
    final tip = await _node!.tipHeight();
    setState(() {
      _explorerTip = tip;
      _nextBlockHeightToLoad = tip;
      _scanHeightForTx = tip;
      _explorerBlocks.clear();
      _explorerTxs.clear();
    });
    // Preload first pages
    await Future.wait([
      _loadMoreBlocks(),
      _loadMoreTxs(),
    ]);
  }

  Future<void> _onExplorerNewBlock() async {
    // If explorer was initialized, prepend the newest block and its txs
    if (_node == null || _explorerTip < 0) return;
    final tip = await _node!.tipHeight();
    if (tip <= _explorerTip) return;
    final b = await _node!.getBlockByHeight(tip);
    if (b == null) {
      setState(() => _explorerTip = tip);
      return;
    }
    final newTxs = <pc.TxModel>[];
    for (final id in b.txIds) {
      final tx = await _node!.getTransactionById(id);
      if (tx != null) newTxs.add(tx);
    }
    setState(() {
      _explorerTip = tip;
      _explorerBlocks.insert(0, b);
      _explorerTxs.insertAll(0, newTxs);
      if (_scanHeightForTx < tip) {
        _scanHeightForTx = tip - 1;
      }
    });
  }

  Future<void> _loadMoreBlocks({int pageSize = 20}) async {
    if (_loadingBlocks || _node == null) return;
    if (_nextBlockHeightToLoad < 0) return;
    setState(() => _loadingBlocks = true);
    final start = _nextBlockHeightToLoad;
    final end = (_nextBlockHeightToLoad - pageSize + 1).clamp(0, _nextBlockHeightToLoad);
    final loaded = <pc.BlockModel>[];
    for (int h = start; h >= end; h--) {
      final b = await _node!.getBlockByHeight(h);
      if (b != null) loaded.add(b);
    }
    setState(() {
      _explorerBlocks.addAll(loaded);
      _nextBlockHeightToLoad = end - 1;
      _loadingBlocks = false;
    });
  }

  Future<void> _loadMoreTxs({int minCount = 30}) async {
    if (_loadingTxs || _node == null) return;
    if (_scanHeightForTx < 0) return;
    setState(() => _loadingTxs = true);
    // Walk blocks descending until we collect at least minCount new TXs or reach 0
    final collected = <pc.TxModel>[];
    while (_scanHeightForTx >= 0 && collected.length < minCount) {
      final b = await _node!.getBlockByHeight(_scanHeightForTx);
      _scanHeightForTx--;
      if (b == null) continue;
      for (final id in b.txIds) {
        final tx = await _node!.getTransactionById(id);
        if (tx != null) collected.add(tx);
      }
    }
    setState(() {
      _explorerTxs.addAll(collected);
      _loadingTxs = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set up infinite scrolling listeners once
    _blocksScroll.removeListener(_onBlocksScroll);
    _blocksScroll.addListener(_onBlocksScroll);
    _txsScroll.removeListener(_onTxsScroll);
    _txsScroll.addListener(_onTxsScroll);
  }

  void _onBlocksScroll() {
    if (_blocksScroll.position.pixels >= _blocksScroll.position.maxScrollExtent - 200) {
      _loadMoreBlocks();
    }
  }

  void _onTxsScroll() {
    if (_txsScroll.position.pixels >= _txsScroll.position.maxScrollExtent - 200) {
      _loadMoreTxs();
    }
  }

  Widget _explorerView() {
    // Initialize lazily to avoid extra work when the tab isn't opened
    if (_explorerTip < 0 && _nodeStarted) {
      // fire and forget; UI will rebuild on setState
      // ignore: discarded_futures
      _initExplorer();
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.explore, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Block Explorer', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _initExplorer,
              icon: const Icon(Icons.refresh, color: Colors.blue),
              label: const Text('Reload'),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _explorerSearchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Search block height, block ID, or tx ID',
                  prefixIcon: Icon(Icons.search, color: Colors.blue),
                ),
                onSubmitted: (_) => _onExplorerSearch(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _onExplorerSearch,
              icon: const Icon(Icons.search, color: Colors.white),
              label: const Text('Search', style: TextStyle(color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const TabBar(
                      tabs: [
                        Tab(text: 'Blocks', icon: Icon(Icons.view_in_ar)),
                        Tab(text: 'Transactions', icon: Icon(Icons.swap_horiz)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _explorerBlocksList(),
                        _explorerTxsList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onExplorerSearch() async {
    final q = _explorerSearchCtrl.text.trim();
    if (q.isEmpty || _node == null) return;
    // Height search if numeric
    final h = int.tryParse(q);
    if (h != null) {
      final b = await _node!.getBlockByHeight(h);
      if (b != null) {
        // Show details directly
        // ignore: discarded_futures
        _showBlockDetails(b);
      } else {
        MetricsBus.I.logWarn('Block height not found: $h');
      }
      return;
    }
    // Try block by id
    final b = await _node!.getBlockById(q);
    if (b != null) {
      // ignore: discarded_futures
      _showBlockDetails(b);
      return;
    }
    // Try tx by id
    final tx = await _node!.getTransactionById(q);
    if (tx != null) {
      final j = const JsonEncoder.withIndent('  ').convert(tx.toJson());
      // ignore: discarded_futures
      _showTextDialog('Transaction ${_shortKey(tx.txId)}', j);
      return;
    }
    MetricsBus.I.logWarn('No block/tx found for "$q"');
  }

  Widget _explorerBlocksList() {
    if (_explorerTip < 0 && !_nodeStarted) {
      return const Center(child: Text('Starting node...'));
    }
    return ListView.separated(
      controller: _blocksScroll,
      itemCount: _explorerBlocks.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == _explorerBlocks.length) {
          final done = _nextBlockHeightToLoad < 0;
          if (done) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No more blocks')));
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Loading blocks...', style: Theme.of(context).textTheme.labelSmall),
            ]),
          );
        }
        final b = _explorerBlocks[i];
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.view_in_ar, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('#${b.header.height}', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(DateTime.fromMillisecondsSinceEpoch(b.header.timestampMs).toIso8601String(),
                    style: Theme.of(context).textTheme.labelSmall),
              ]),
              const SizedBox(height: 6),
              SelectableText('blockId: ${b.header.blockId}'),
              SelectableText('prev: ${b.header.prevBlockId}'),
              Wrap(spacing: 8, children: [
                Chip(label: Text('tx: ${b.txIds.length}')),
                Chip(label: Text(_shortKey(b.header.txMerkleRoot))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: () => _showBlockDetails(b),
                  icon: const Icon(Icons.info, color: Colors.blue),
                  label: const Text('Details'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: b.header.blockId)),
                  icon: const Icon(Icons.copy, color: Colors.blue),
                  label: const Text('Copy ID'),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _explorerTxsList() {
    return ListView.separated(
      controller: _txsScroll,
      itemCount: _explorerTxs.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == _explorerTxs.length) {
          final done = _scanHeightForTx < 0;
          if (done) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No more transactions')));
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Loading transactions...', style: Theme.of(context).textTheme.labelSmall),
            ]),
          );
        }
        final t = _explorerTxs[i];
        return _txRow(t);
      },
    );
  }
  // endregion

  // region: API
  Widget _apiView() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.api, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('External API (postMessage)', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Switch(
              value: _apiExposed,
              onChanged: !_nodeStarted || !jsApiSupported
                  ? null
                  : (v) {
                      setState(() => _apiExposed = v);
                      if (v) {
                        registerJsApi(_node!);
                      } else {
                        unregisterJsApi();
                      }
                    },
            ),
          ]),
          const SizedBox(height: 6),
          if (!jsApiSupported) const Text('JS bridge not supported on this platform.'),
          if (jsApiSupported) ...[
            Text('How to call from browser console or another window/tab:', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            _codeBlock('''
// Request
const req = { target: 'peoplechain', id: '1', method: 'getInfo', params: {} };
window.postMessage(req, '*');

// Listen for response
window.addEventListener('message', (e) => {
  if (e.data && e.data.target === 'peoplechain' && e.data.id === '1') {
    console.log('Response', e.data);
  }
});

// Other methods:
// recentPeers {limit}
// createOffer, acceptOffer {offer}, acceptAnswer {answer}
// sendText {toEd25519, text}
// getTx {txId}, getMessages {withPubKey, limit}
// tipHeight {}
// getBlockByHeight {height}, getBlockById {blockId}
'''),
            const SizedBox(height: 12),
            _Card(
              child: _apiSelfTestForm(),
            ),
            if (_apiLastResponse != null) ...[
              const SizedBox(height: 8),
              _Card(child: SelectableText(_apiLastResponse!)),
            ]
          ],
        ],
      ),
    );
  }

  Widget _apiSelfTestForm() {
    final reqCtrl = TextEditingController(text: '{"target":"peoplechain","id":"demo","method":"getInfo","params":{}}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.play_circle, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('Send test request to self', style: Theme.of(context).textTheme.titleMedium),
        ]),
        const SizedBox(height: 6),
        TextField(controller: reqCtrl, maxLines: 4, minLines: 1),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final map = (jsonDecode(reqCtrl.text) as Map).cast<String, dynamic>();
                final resp = await sendTestPostMessage(map);
                setState(() => _apiLastResponse = const JsonEncoder.withIndent('  ').convert(resp));
              } catch (e) {
                setState(() => _apiLastResponse = 'Error: $e');
              }
            },
            icon: const Icon(Icons.send, color: Colors.blue),
            label: const Text('Post'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _apiLastResponse = null),
            icon: const Icon(Icons.clear, color: Colors.red),
            label: const Text('Clear'),
          )
        ])
      ],
    );
  }

  Widget _codeBlock(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
  // endregion

  Future<void> _showTextDialog(String title, String text) async {
    await showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: Text(title),
        content: SelectableText(text),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
    });
  }

  // region: Details Modals
  Future<void> _showPeerDetails(pc.PeerRecord p) async {
    final json = const JsonEncoder.withIndent('  ').convert({
      'nodeId': p.nodeId,
      'alias': p.alias,
      'ed25519': p.ed25519PubKey,
      'x25519': p.x25519PubKey,
      'lastSeenMs': p.lastSeenMs,
      'lastSeen': DateTime.fromMillisecondsSinceEpoch(p.lastSeenMs).toIso8601String(),
      'transports': p.transports,
    });
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.person_search, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Peer Details', style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.red),
                  )
                ]),
                const SizedBox(height: 8),
                _kvRow('Alias', p.alias ?? '—', copyValue: p.alias ?? ''),
                _kvRow('Node ID', p.nodeId, copyValue: p.nodeId),
                _kvRow('ed25519', p.ed25519PubKey, copyValue: p.ed25519PubKey),
                _kvRow('x25519', p.x25519PubKey, copyValue: p.x25519PubKey),
                _kvRow('Last seen', _ago(p.lastSeenMs), copyValue: DateTime.fromMillisecondsSinceEpoch(p.lastSeenMs).toIso8601String()),
                _kvRow('Transports', p.transports.join(', '), copyValue: p.transports.join(',')),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: json)),
                    icon: const Icon(Icons.copy_all, color: Colors.blue),
                    label: const Text('Copy JSON'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.blue),
                    label: const Text('Close'),
                  ),
                ])
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChainDetails() async {
    // Build summary and simple visualization of the most recent blocks we already hold
    final blocks = _recentBlocks;
    int txTotal = 0;
    if (blocks.isNotEmpty) {
      for (final b in blocks) {
        txTotal += b.txIds.length;
      }
    }
    final avgTx = blocks.isEmpty ? 0 : (txTotal / blocks.length);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.insights, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Chain Details', style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.red))
                ]),
                const SizedBox(height: 8),
                _kvRow('Tip height', '$_tip'),
                _kvRow('Recent blocks (loaded)', '${blocks.length}'),
                _kvRow('Avg TX per block', avgTx.toStringAsFixed(2)),
                const SizedBox(height: 12),
                Text('Block timeline', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: blocks.isEmpty
                      ? const Center(child: Text('No blocks to visualize'))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: blocks.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => _blockViz(blocks[i]),
                        ),
                ),
                const SizedBox(height: 12),
                Text('Recent blocks', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                SizedBox(
                  height: 240,
                  child: blocks.isEmpty
                      ? const Center(child: Text('No blocks'))
                      : ListView.separated(
                          itemCount: blocks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final b = blocks[i];
                            return _Card(
                              child: Row(
                                children: [
                                  Expanded(child: Text('#${b.header.height}  ${b.header.blockId.substring(0, 10)}...  tx:${b.txIds.length}')),
                                  OutlinedButton.icon(
                                    onPressed: () => _showBlockDetails(b),
                                    icon: const Icon(Icons.unfold_more, color: Colors.blue),
                                    label: const Text('Expand'),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.blue),
                    label: const Text('Close'),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _blockViz(pc.BlockModel b) {
    final headerColor = Theme.of(context).colorScheme.primaryContainer;
    final payloadColor = Theme.of(context).colorScheme.tertiary;
    return InkWell(
      onTap: () => _showBlockDetails(b),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Header', style: Theme.of(context).textTheme.labelSmall),
                  Text('#${b.header.height} • ${b.header.blockId.substring(0, 8)}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.arrow_downward, color: Colors.blue, size: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: payloadColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Payload', style: Theme.of(context).textTheme.labelSmall),
                  Row(children: [
                    const Icon(Icons.article, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text('${b.txIds.length} tx', style: Theme.of(context).textTheme.bodySmall),
                  ])
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortKey(String v, {int head = 6, int tail = 4}) {
    if (v.length <= head + tail) return v;
    return '${v.substring(0, head)}…${v.substring(v.length - tail)}';
  }

  Widget _txRow(pc.TxModel t) {
    final isFromMe = (_selfEd25519 != null && t.from == _selfEd25519);
    final isToMe = (_selfEd25519 != null && t.to == _selfEd25519);
    final fromLabel = isFromMe ? 'Me' : _shortKey(t.from);
    final toLabel = isToMe ? 'Me' : _shortKey(t.to);
    final payload = t.payload;
    final type = payload.type;
    final ts = _ago(t.timestampMs);

    IconData typeIcon;
    String summary;
    if (type == 'text') {
      typeIcon = Icons.chat_bubble_outline;
      final txt = payload.text ?? '';
      summary = txt.isEmpty ? '(empty)' : (txt.length > 80 ? '${txt.substring(0, 80)}…' : txt);
    } else if (type == 'media' || type == 'file') {
      typeIcon = Icons.attachment;
      final size = payload.sizeBytes != null ? ' • ${(payload.sizeBytes! / 1024).toStringAsFixed(1)} KB' : '';
      summary = '${payload.mime ?? type}$size';
    } else {
      typeIcon = Icons.device_unknown;
      summary = type;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Chip(label: Text('From: $fromLabel')),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward, size: 18, color: Colors.blue),
            const SizedBox(width: 6),
            Chip(label: Text('To: $toLabel')),
            const Spacer(),
            Text(ts, style: Theme.of(context).textTheme.labelSmall),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(typeIcon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(summary)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: t.txId)),
              icon: const Icon(Icons.copy, color: Colors.blue),
              label: const Text('Copy TX ID'),
            ),
            const SizedBox(width: 8),
            if (type == 'text' && (t.payload.text?.isNotEmpty ?? false))
              OutlinedButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: t.payload.text!)),
                icon: const Icon(Icons.copy, color: Colors.blue),
                label: const Text('Copy Text'),
              ),
          ])
        ],
      ),
    );
  }

  Future<void> _showBlockDetails(pc.BlockModel b) async {
    String json = const JsonEncoder.withIndent('  ').convert(b.toJson());
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SafeArea(
            top: false,
            child: StatefulBuilder(
              builder: (context, setModal) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.view_in_ar, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Block #${b.header.height}', style: Theme.of(context).textTheme.titleMedium)),
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.red)),
                    ]),
                    const SizedBox(height: 8),
                    _kvRow('Block ID', b.header.blockId, copyValue: b.header.blockId),
                    _kvRow('Prev', b.header.prevBlockId, copyValue: b.header.prevBlockId),
                    _kvRow('Timestamp', DateTime.fromMillisecondsSinceEpoch(b.header.timestampMs).toIso8601String(),
                        copyValue: b.header.timestampMs.toString()),
                    _kvRow('Merkle Root', b.header.txMerkleRoot, copyValue: b.header.txMerkleRoot),
                    _kvRow('Proposer', b.header.proposer, copyValue: b.header.proposer),
                    const SizedBox(height: 8),
                    Text('Transactions', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    if (b.txIds.isEmpty) const Text('No transactions') else ...[
                      SizedBox(
                        height: 180,
                        child: ListView.separated(
                          itemCount: b.txIds.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final txId = b.txIds[i];
                            return _Card(
                              child: Row(
                                children: [
                                  Expanded(child: Text(txId)),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final tx = await _node?.getTransactionById(txId);
                                      if (tx != null) {
                                        final txJson = const JsonEncoder.withIndent('  ').convert(tx.toJson());
                                        unawaited(_showTextDialog('TX $txId', txJson));
                                      } else {
                                        MetricsBus.I.logWarn('TX not found: $txId');
                                      }
                                    },
                                    icon: const Icon(Icons.info, color: Colors.blue),
                                    label: const Text('View'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => Clipboard.setData(ClipboardData(text: txId)),
                                    icon: const Icon(Icons.copy, color: Colors.blue),
                                    label: const Text('Copy ID'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    ],
                    const SizedBox(height: 8),
                    Row(children: [
                      OutlinedButton.icon(
                        onPressed: () => Clipboard.setData(ClipboardData(text: json)),
                        icon: const Icon(Icons.copy_all, color: Colors.blue),
                        label: const Text('Copy Block JSON'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.blue),
                        label: const Text('Close'),
                      ),
                    ])
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _kvRow(String k, String v, {String? copyValue}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: Theme.of(context).textTheme.labelSmall)),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(v)),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: copyValue ?? v)),
            icon: const Icon(Icons.copy, color: Colors.blue, size: 18),
            tooltip: 'Copy',
          )
        ],
      ),
    );
  }
  // endregion

  Future<String?> _prompt(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(context: context, builder: (_) {
      return AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, maxLines: 3, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(ctrl.text), child: const Text('OK')),
        ],
      );
    });
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

// _ChartSeries removed in favor of in-place updated List<FlSpot>

class _TestCardContent extends StatefulWidget {
  final TestCaseDef def;
  const _TestCardContent({required this.def});
  @override
  State<_TestCardContent> createState() => _TestCardContentState();
}

class _TestCardContentState extends State<_TestCardContent> {
  bool _running = false;
  String _status = 'Idle';
  Duration _lastDuration = Duration.zero;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.check_circle, color: _status == 'Pass' ? Colors.green : Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.def.title, style: Theme.of(context).textTheme.titleMedium)),
          Text(_status),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.play_arrow, color: Colors.blue),
            label: const Text('Run'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _running ? null : () => setState(() { _status = 'Idle'; _error = null; }),
            icon: const Icon(Icons.clear, color: Colors.red),
            label: const Text('Clear'),
          ),
        ]),
        const SizedBox(height: 4),
        Text(widget.def.description, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text('Last duration: ${_lastDuration.inMilliseconds} ms', style: Theme.of(context).textTheme.labelSmall),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  Future<void> _run() async {
    setState(() { _running = true; _status = 'Running'; _error = null; });
    final res = await TestHarness.I.run(widget.def);
    setState(() {
      _running = false;
      _lastDuration = res.duration;
      _status = res.passed ? 'Pass' : 'Fail';
      _error = res.error;
    });
  }
}
