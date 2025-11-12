import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../p2p_manager.dart';
import 'webrtc_adapter.dart';
import 'webrtc_signal_api.dart';

/// Lightweight HTTP client for the PeopleChain Discovery Relay.
///
/// Responsibilities:
/// - Announce presence: POST /announce { nodeId, alias? }
/// - Send signaling messages: POST /send { from, to, type, data }
/// - Long-poll inbox: GET /poll?node=ID&timeout=25
/// - Drive automatic WebRTC offer/answer exchange without any UI steps.
///
/// Design notes:
/// - Uses package:http to support Web and IO.
/// - Heartbeat announce every 60s to keep presence fresh.
/// - Poll loop with exponential backoff on errors.
/// - Sends one outstanding offer per known online peer and avoids spamming.
/// - All signaling payloads are opaque base64 strings (SDP JSON payload created by WebRtcAdapter).
class DiscoveryAdapter implements P2PAdapter {
  // Compile-time dart-define overrides (set with --dart-define)
  static const String _hostEnv = String.fromEnvironment('PEOPLECHAIN_DISCOVERY_HOST', defaultValue: '');
  static const String _portEnv = String.fromEnvironment('PEOPLECHAIN_DISCOVERY_PORT', defaultValue: '');

  final String nodeId;
  final String ed25519PubKey;
  final String x25519PubKey;
  final String? alias;
  final WebRtcSignalApi _webrtc;
  final http.Client _http;

  final _peerCtrl = StreamController<PeerInfo>.broadcast();

  bool _running = false;
  String _host;
  int _port;
  Timer? _heartbeat;
  Future<void>? _pollFuture;
  DateTime? _startedAt;
  DateTime? _lastAnnounceAt;
  // Track peers we've attempted to connect to via offer to avoid duplicates
  final Set<String> _outboundOffers = <String>{};

  DiscoveryAdapter({
    required this.nodeId,
    required this.ed25519PubKey,
    required this.x25519PubKey,
    required WebRtcSignalApi webrtc,
    this.alias,
    http.Client? client,
    String? host,
    int? port,
  })  : _webrtc = webrtc,
        _http = client ?? http.Client(),
        _host = host ?? (_hostEnv.isNotEmpty ? _hostEnv : '127.0.0.1'),
        _port = port ?? (int.tryParse(_portEnv) ?? 8081);

  Uri _u(String path, [Map<String, String>? q]) => Uri(
        scheme: 'http',
        host: _host,
        port: _port,
        path: path,
        queryParameters: q,
      );

  @override
  bool get isSupported => true; // Feature-flagged by reachability; safe to start on all platforms

  @override
  Stream<PeerInfo> onPeerDiscovered() => _peerCtrl.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _startedAt = DateTime.now();
    // Initial announce; if it fails, we still keep running and rely on backoff to retry
    await _announce(silent: true);
    _startHeartbeat();
    _startPollingLoop();
    // Opportunistically connect to currently online peers listed by announce
    try {
      final online = await _fetchOnlinePeers();
      for (final p in online) {
        if (p.nodeId != nodeId) {
          _maybeSendOffer(p.nodeId);
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _running = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    try { await _pollFuture; } catch (_) {}
    _outboundOffers.clear();
    await _peerCtrl.close();
    _http.close();
  }

  Future<void> _announce({bool silent = false}) async {
    try {
      final res = await _http.post(_u('/announce'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        'nodeId': nodeId,
        if (alias != null) 'alias': alias,
      })).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        _lastAnnounceAt = DateTime.now();
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final online = (j['online'] as List?)?.cast<Map>() ?? const [];
        // Surface online peers to peer store quickly
        for (final e in online) {
          final id = (e['nodeId'] ?? '').toString();
          if (id.isEmpty || id == nodeId) continue;
          // We do not know keys from presence alone, skip emitting PeerInfo here.
          // Actual PeerInfo will be emitted once SDP is processed by WebRTC adapter.
        }
      }
    } catch (e) {
      if (!silent) {
        // ignore noisy logs in production; rely on debug console
      }
    }
  }

  // Expose status for monitors
  bool get isRunning => _running;
  String get host => _host;
  int get port => _port;
  DateTime? get startedAt => _startedAt;
  DateTime? get lastAnnounceAt => _lastAnnounceAt;

  Map<String, dynamic> status() {
    final now = DateTime.now();
    final up = _startedAt == null ? 0 : now.difference(_startedAt!).inSeconds;
    return {
      'running': _running,
      'host': _host,
      'port': _port,
      'started_at_ms': _startedAt?.millisecondsSinceEpoch,
      'last_announce_ms': _lastAnnounceAt?.millisecondsSinceEpoch,
      'uptime_s': up,
    };
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_running) return;
      // ignore: discarded_futures
      _announce(silent: true);
    });
  }

  Future<List<_OnlinePeer>> _fetchOnlinePeers() async {
    try {
      final res = await _http.post(_u('/announce'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        'nodeId': nodeId,
        if (alias != null) 'alias': alias,
      })).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200 || res.body.isEmpty) return const [];
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final online = (j['online'] as List?)?.cast<Map>() ?? const [];
      return online
          .map((e) => _OnlinePeer(nodeId: (e['nodeId'] ?? '').toString(), alias: (e['alias'] as String?)))
          .where((p) => p.nodeId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _startPollingLoop() {
    _pollFuture = _pollLoop();
  }

  Future<void> _pollLoop() async {
    int backoffMs = 1000;
    const int maxBackoffMs = 30000;
    while (_running) {
      try {
        // Long-poll up to 25s; server returns immediately on messages
        final uri = _u('/poll', {'node': nodeId, 'timeout': '25'});
        final res = await _http.get(uri).timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          backoffMs = 1000; // reset backoff on success
          if (res.body.isNotEmpty) {
            final body = jsonDecode(res.body) as Map<String, dynamic>;
            final msgs = (body['messages'] as List?)?.cast<Map>() ?? const [];
            for (final m in msgs) {
              final from = (m['from'] ?? '').toString();
              final type = (m['type'] ?? '').toString();
              final data = m['data'];
              if (from.isEmpty || type.isEmpty) continue;
              if (type == 'offer') {
                final base64Offer = (data ?? '').toString();
                final answer = await _webrtc.acceptOfferAndCreateAnswer(base64Offer);
                // Send back answer
                await _http.post(_u('/send'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({
                  'from': nodeId,
                  'to': from,
                  'type': 'answer',
                  'data': answer,
                }));
              } else if (type == 'answer') {
                final base64Answer = (data ?? '').toString();
                await _webrtc.acceptAnswer(base64Answer);
              }
            }
          }
        } else {
          // HTTP error -> apply backoff
          await Future.delayed(Duration(milliseconds: backoffMs));
          backoffMs = (backoffMs * 2).clamp(1000, maxBackoffMs);
        }
      } catch (_) {
        await Future.delayed(Duration(milliseconds: backoffMs));
        backoffMs = (backoffMs * 2).clamp(1000, maxBackoffMs);
      }

      // Opportunistically attempt outbound offers to new online peers
      try {
        final online = await _fetchOnlinePeers();
        for (final p in online) {
          if (p.nodeId != nodeId) {
            _maybeSendOffer(p.nodeId);
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _maybeSendOffer(String remoteNodeId) async {
    if (_outboundOffers.contains(remoteNodeId)) return;
    _outboundOffers.add(remoteNodeId);
    try {
      final offer = await _webrtc.createOfferPayload();
      await _http.post(_u('/send'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        'from': nodeId,
        'to': remoteNodeId,
        'type': 'offer',
        'data': offer,
      })).timeout(const Duration(seconds: 5));
    } catch (_) {
      // allow retry on next online fetch
      _outboundOffers.remove(remoteNodeId);
    }
  }
}

class _OnlinePeer {
  final String nodeId;
  final String? alias;
  const _OnlinePeer({required this.nodeId, this.alias});
}
