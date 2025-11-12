import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../p2p_manager.dart';

class BluetoothAdapter implements P2PAdapter {
  final String nodeId;
  final String ed25519PubKey;
  final String x25519PubKey;
  final String? alias;

  final _peerCtrl = StreamController<PeerInfo>.broadcast();

  BluetoothAdapter({required this.nodeId, required this.ed25519PubKey, required this.x25519PubKey, this.alias});

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Stream<PeerInfo> onPeerDiscovered() => _peerCtrl.stream;

  @override
  Future<void> start() async {
    // NOTE: Placeholder. Advertising as a BLE peripheral is not supported by flutter_blue_plus.
    // A full BLE adapter (advertise + GATT handshake) can be added with a peripheral-capable plugin.
  }

  @override
  Future<void> stop() async {
    await _peerCtrl.close();
  }
}
