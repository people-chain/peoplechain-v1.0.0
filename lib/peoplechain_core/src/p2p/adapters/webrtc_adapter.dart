import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../p2p_manager.dart';
import 'package:pocket_coach/testing/metrics_bus.dart';
import 'webrtc_signal_api.dart';

class WebRtcQrPayload {
  static String encode(Map<String, dynamic> map) => base64Encode(utf8.encode(jsonEncode(map)));
  static Map<String, dynamic> decode(String base64Payload) => jsonDecode(utf8.decode(base64Decode(base64Payload))) as Map<String, dynamic>;
}

class WebRtcAdapter implements P2PAdapter, WebRtcSignalApi {
  final String nodeId;
  final String ed25519PubKey;
  final String x25519PubKey;
  final String? alias;

  // Ping helpers for RTT measurement (used by Web Testing Dashboard)
  final Map<int, Completer<Duration>> _pendingPings = {};

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  final _peerCtrl = StreamController<PeerInfo>.broadcast();
  final _msgCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _openCtrl = StreamController<void>.broadcast();
  bool _running = false;
  bool _answerApplied = false;

  WebRtcAdapter({required this.nodeId, required this.ed25519PubKey, required this.x25519PubKey, this.alias});

  @override
  bool get isSupported => true; // WebRTC supported on mobile and web

  @override
  Stream<PeerInfo> onPeerDiscovered() => _peerCtrl.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _dc?.close();
    await _pc?.close();
    await _peerCtrl.close();
    await _msgCtrl.close();
    await _openCtrl.close();
    _dc = null;
    _pc = null;
    _answerApplied = false;
  }

  Future<RTCPeerConnection> _ensurePc() async {
    if (_pc != null) return _pc!;
    print('[WebRTC] Creating RTCPeerConnection');
    final pc = await createPeerConnection({
      'iceServers': [
        // Fully P2P; leave empty to use local ICE only
      ]
    }, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });
    _pc = pc;
    pc.onIceCandidate = (candidate) {
      // For manual/QR, we wait for gathering complete and then read localDescription (non-trickle)
      if (candidate == null) return;
      print('[WebRTC] onIceCandidate: ${candidate.candidate?.substring(0, 24) ?? 'null'}...');
    };
    pc.onIceGatheringState = (state) {
      print('[WebRTC] ICE gathering state: $state');
    };
    pc.onConnectionState = (state) {
      print('[WebRTC] Connection state: $state');
    };
    pc.onDataChannel = (chan) {
      _attachDataChannel(chan);
    };
    return pc;
  }

  Future<void> _waitForIceGatheringComplete(RTCPeerConnection pc, {Duration timeout = const Duration(seconds: 5)}) async {
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final c = Completer<void>();
    final prev = pc.onIceGatheringState;
    void handle(RTCIceGatheringState s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !c.isCompleted) {
        c.complete();
      }
    }
    pc.onIceGatheringState = (s) {
      prev?.call(s);
      handle(s);
    };
    try {
      await c.future.timeout(timeout);
    } catch (_) {
      print('[WebRTC] ICE gathering timeout; proceeding with current candidates');
    }
  }

  // region: Manual/QR SDP helpers
  /// Builds an SDP offer and returns a base64-encoded JSON payload containing identifiers.
  Future<String> createOfferPayload() async {
    final pc = await _ensurePc();
    _dc ??= await pc.createDataChannel('pc-data', RTCDataChannelInit()..ordered = true);
    _attachDataChannel(_dc!);
    print('[WebRTC] Creating offer...');
    final offer = await pc.createOffer({'offerToReceiveAudio': false, 'offerToReceiveVideo': false});
    await pc.setLocalDescription(offer);
    await _waitForIceGatheringComplete(pc);
    String sdp;
    try {
      final local = await pc.getLocalDescription();
      sdp = (local?.sdp ?? offer.sdp) ?? '';
    } catch (_) {
      sdp = offer.sdp ?? '';
    }

    final payload = jsonEncode({
      'type': 'offer',
      'sdp': sdp,
      'nodeId': nodeId,
      'ed25519': ed25519PubKey,
      'x25519': x25519PubKey,
      if (alias != null) 'alias': alias,
    });
    return base64Encode(utf8.encode(payload));
  }

  /// Accepts a base64 JSON offer payload, sets remote, creates answer, and returns base64 JSON answer.
  Future<String> acceptOfferAndCreateAnswer(String base64Payload) async {
    final pc = await _ensurePc();
    // onDataChannel handled in _ensurePc
    final decoded = WebRtcQrPayload.decode(base64Payload);
    final offerSdp = decoded['sdp'] as String;
    final remoteNodeId = decoded['nodeId'] as String?;
    final remoteEd = decoded['ed25519'] as String?;
    final remoteX = decoded['x25519'] as String?;
    if (remoteNodeId != null && remoteEd != null && remoteX != null && remoteNodeId != nodeId) {
      _peerCtrl.add(PeerInfo(nodeId: remoteNodeId, ed25519PubKey: remoteEd, x25519PubKey: remoteX, alias: decoded['alias'] as String?, transports: const ['webrtc']));
    }
    print('[WebRTC] Accepting offer and creating answer...');
    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    final answer = await pc.createAnswer({});
    await pc.setLocalDescription(answer);
    await _waitForIceGatheringComplete(pc);
    String sdp;
    try {
      final local = await pc.getLocalDescription();
      sdp = (local?.sdp ?? answer.sdp) ?? '';
    } catch (_) {
      sdp = answer.sdp ?? '';
    }
    final payload = jsonEncode({
      'type': 'answer',
      'sdp': sdp,
      'nodeId': nodeId,
      'ed25519': ed25519PubKey,
      'x25519': x25519PubKey,
      if (alias != null) 'alias': alias,
    });
    return base64Encode(utf8.encode(payload));
  }

  /// Applies a base64 JSON answer payload to finalize the connection.
  Future<void> acceptAnswer(String base64Payload) async {
    // Idempotent: if already applied or channel is open, treat as success
    if (_answerApplied || isOpen) {
      print('[WebRTC] acceptAnswer called but already applied/open; ignoring');
      return;
    }

    final decoded = WebRtcQrPayload.decode(base64Payload);
    final answerSdp = decoded['sdp'] as String;
    final remoteNodeId = decoded['nodeId'] as String?;
    final remoteEd = decoded['ed25519'] as String?;
    final remoteX = decoded['x25519'] as String?;
    if (remoteNodeId != null && remoteEd != null && remoteX != null && remoteNodeId != nodeId) {
      _peerCtrl.add(PeerInfo(nodeId: remoteNodeId, ed25519PubKey: remoteEd, x25519PubKey: remoteX, alias: decoded['alias'] as String?, transports: const ['webrtc']));
    }
    final pc = await _ensurePc();
    try {
      print('[WebRTC] Applying answer...');
      await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
      _answerApplied = true;
    } catch (e) {
      final msg = e.toString();
      // Web (libwebrtc) throws when we try to re-apply in stable state. Treat as success.
      if (msg.contains('Called in wrong state') || msg.contains('stable') || msg.contains('InvalidStateError')) {
        print('[WebRTC] Answer already applied (stable); treating as success');
        _answerApplied = true;
        return;
      }
      rethrow;
    }
  }
  // endregion

  // region: Data channel helpers
  void _attachDataChannel(RTCDataChannel chan) {
    _dc = chan;
    print('[WebRTC] Data channel attached: ${chan.label}');
    _dc!.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary) return; // protocol uses JSON text frames
      try {
        // Approximate bytes received as UTF-8 length of text payload
        try {
          final downBytes = utf8.encode(msg.text).length;
          MetricsBus.I.recordNetDownBytes(downBytes);
        } catch (_) {}
        final map = jsonDecode(msg.text) as Map<String, dynamic>;
        // Intercept lightweight test ping/pong so SyncEngine doesn't see it
        final testType = map['__test'] as String?;
        if (testType == 'ping') {
          // Echo back with pong
          final t = (map['t'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
          // ignore: discarded_futures
          sendJson({'__test': 'pong', 't': t});
          return;
        } else if (testType == 'pong') {
          final t = (map['t'] as num?)?.toInt();
          if (t != null) {
            final c = _pendingPings.remove(t);
            if (c != null && !c.isCompleted) {
              final rtt = DateTime.now().millisecondsSinceEpoch - t;
              c.complete(Duration(milliseconds: rtt));
            }
            return;
          }
        }
        _msgCtrl.add(map);
      } catch (_) {
        // ignore malformed
      }
    };
    _dc!.onDataChannelState = (RTCDataChannelState state) {
      print('[WebRTC] Data channel state: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _openCtrl.add(null);
      }
    };
  }

  Stream<Map<String, dynamic>> onJsonMessage() => _msgCtrl.stream;
  Stream<void> onOpen() => _openCtrl.stream;
  bool get isOpen => _dc?.state == RTCDataChannelState.RTCDataChannelOpen;
  Future<void> sendJson(Map<String, dynamic> map) async {
    if (_dc == null) return;
    try {
      final text = jsonEncode(map);
      _dc!.send(RTCDataChannelMessage(text));
      // Approximate bytes sent as UTF-8 length of text payload
      try {
        final upBytes = utf8.encode(text).length;
        MetricsBus.I.recordNetUpBytes(upBytes);
      } catch (_) {}
    } catch (_) {
      // ignore
    }
  }
  // endregion

  // region: Test utilities
  /// Sends a single ping and awaits a pong to compute RTT. Returns null on timeout.
  Future<Duration?> pingOnce({Duration timeout = const Duration(seconds: 3)}) async {
    if (_dc == null) return null;
    final t = DateTime.now().millisecondsSinceEpoch;
    final c = Completer<Duration>();
    _pendingPings[t] = c;
    await sendJson({'__test': 'ping', 't': t});
    try {
      return await c.future.timeout(timeout);
    } catch (_) {
      _pendingPings.remove(t);
      return null;
    }
  }
  // endregion
}
