import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../p2p_manager.dart';

/// Placeholder Wi‑Fi Direct adapter. Real implementation requires a platform plugin.
class WifiDirectAdapter implements P2PAdapter {
  final String nodeId;
  final String ed25519PubKey;
  final String x25519PubKey;
  final String? alias;

  final _peerCtrl = StreamController<PeerInfo>.broadcast();

  WifiDirectAdapter({required this.nodeId, required this.ed25519PubKey, required this.x25519PubKey, this.alias});

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    // Limit to Android for now
    return defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  Stream<PeerInfo> onPeerDiscovered() => _peerCtrl.stream;

  @override
  Future<void> start() async {
    // TODO: Implement Wi‑Fi Direct discovery + payload exchange
  }

  @override
  Future<void> stop() async {
    await _peerCtrl.close();
  }
}
