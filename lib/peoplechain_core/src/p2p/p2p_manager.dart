import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'peer_store.dart';
import 'adapters/webrtc_adapter.dart';
import 'adapters/discovery_adapter.dart';
import 'adapters/mdns_adapter.dart';
import 'adapters/bluetooth_adapter.dart';
import 'adapters/wifidirect_adapter.dart';
import 'adapters/nearby_adapter.dart';

class PeerInfo {
  final String nodeId;
  final String ed25519PubKey;
  final String x25519PubKey;
  final List<String> transports;
  final String? alias;
  const PeerInfo({
    required this.nodeId,
    required this.ed25519PubKey,
    required this.x25519PubKey,
    this.transports = const [],
    this.alias,
  });
}

abstract class P2PAdapter {
  Future<void> start();
  Future<void> stop();
  Stream<PeerInfo> onPeerDiscovered();
  bool get isSupported;
}

class P2PManager {
  final PeerStore peerStore;
  final WebRtcAdapter webrtc;
    final DiscoveryAdapter discovery;
  final MdnsAdapter mdns;
  final BluetoothAdapter bluetooth;
  final WifiDirectAdapter wifiDirect;
  final NearbyAdapter nearby;

  final _peerStreamCtrl = StreamController<PeerInfo>.broadcast();
  StreamSubscription<PeerInfo>? _mdnsSub;
  StreamSubscription<PeerInfo>? _bleSub;
  StreamSubscription<PeerInfo>? _webrtcSub;
  StreamSubscription<PeerInfo>? _discoSub;

  P2PManager._(this.peerStore, this.webrtc, this.discovery, this.mdns, this.bluetooth, this.wifiDirect, this.nearby);

  static Future<P2PManager> create({
    required String nodeId,
    required String ed25519PubKey,
    required String x25519PubKey,
    String? alias,
    WebRtcAdapter? webrtc,
  }) async {
    final store = kIsWeb ? InMemoryPeerStore() : await IsarPeerStore.open();
    final mdns = MdnsAdapter(nodeId: nodeId, ed25519PubKey: ed25519PubKey, x25519PubKey: x25519PubKey, alias: alias);
    // Allow the SDK to inject an existing WebRTC adapter so manual/QR flows and sync share the same instance
    final webrtcAdapter = webrtc ?? WebRtcAdapter(nodeId: nodeId, ed25519PubKey: ed25519PubKey, x25519PubKey: x25519PubKey, alias: alias);
    final disco = DiscoveryAdapter(nodeId: nodeId, ed25519PubKey: ed25519PubKey, x25519PubKey: x25519PubKey, webrtc: webrtcAdapter, alias: alias);
    final ble = BluetoothAdapter(nodeId: nodeId, ed25519PubKey: ed25519PubKey, x25519PubKey: x25519PubKey, alias: alias);
    final wfd = WifiDirectAdapter(nodeId: nodeId, ed25519PubKey: ed25519PubKey, x25519PubKey: x25519PubKey, alias: alias);
    final nb = NearbyAdapter(nodeId: nodeId, ed25519PubKey: ed25519PubKey, x25519PubKey: x25519PubKey, alias: alias);
    return P2PManager._(store, webrtcAdapter, disco, mdns, ble, wfd, nb);
  }

  Stream<PeerInfo> onPeerDiscovered() => _peerStreamCtrl.stream;

  Future<void> start() async {
    await webrtc.start();
    // Prefer Discovery relay when reachable; it will drive offer/answer automatically.
    await discovery.start();
    await mdns.start();
    if (bluetooth.isSupported) {
      await bluetooth.start();
    }
    if (wifiDirect.isSupported) {
      await wifiDirect.start();
    }
    if (nearby.isSupported) {
      await nearby.start();
    }
    _mdnsSub = mdns.onPeerDiscovered().listen(_handlePeer);
    _bleSub = bluetooth.onPeerDiscovered().listen(_handlePeer);
    // Also record peers surfaced via WebRTC offer/answer payloads (manual/QR flows)
    _webrtcSub = webrtc.onPeerDiscovered().listen(_handlePeer);
    _discoSub = discovery.onPeerDiscovered().listen(_handlePeer);
    nearby.onPeerDiscovered().listen(_handlePeer);
  }

  Future<void> stop() async {
    await mdns.stop();
    await bluetooth.stop();
    await wifiDirect.stop();
    await nearby.stop();
    await discovery.stop();
    await webrtc.stop();
    await _mdnsSub?.cancel();
    await _bleSub?.cancel();
    await _webrtcSub?.cancel();
    await _discoSub?.cancel();
  }

  void _handlePeer(PeerInfo p) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    await peerStore.putOrUpdate(PeerRecord(
      nodeId: p.nodeId,
      ed25519PubKey: p.ed25519PubKey,
      x25519PubKey: p.x25519PubKey,
      lastSeenMs: ts,
      transports: p.transports,
      alias: p.alias,
    ));
    _peerStreamCtrl.add(p);
  }
}
