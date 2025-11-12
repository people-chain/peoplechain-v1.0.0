import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:nearby_connections/nearby_connections.dart';

import '../p2p_manager.dart';

/// Discovery via Google Nearby Connections (Android only).
/// Uses P2P_CLUSTER which can leverage Bluetooth, BLE, and Wi‑Fi (including Wi‑Fi Direct)
/// under the hood to discover nearby endpoints.
class NearbyAdapter implements P2PAdapter {
  static const String serviceId = 'peoplechain.nearby';

  final String nodeId;
  final String ed25519PubKey;
  final String x25519PubKey;
  final String? alias;

  final _peerCtrl = StreamController<PeerInfo>.broadcast();
  bool _running = false;

  NearbyAdapter({required this.nodeId, required this.ed25519PubKey, required this.x25519PubKey, this.alias});

  @override
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<PeerInfo> onPeerDiscovered() => _peerCtrl.stream;

  @override
  Future<void> start() async {
    if (!isSupported || _running) return;
    _running = true;
    final hello = jsonEncode({
      'nodeId': nodeId,
      'ed25519': ed25519PubKey,
      'x25519': x25519PubKey,
      if (alias != null) 'alias': alias,
    });
    // Start advertising our presence and accept ephemeral connections to exchange metadata
    try {
      await Nearby().startAdvertising(
        nodeId,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: (id, infoData) async {
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endid, payload) async {
              try {
                final bytes = payload.bytes;
                if (bytes == null) return;
                final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
                final remoteId = map['nodeId'] as String?;
                final ed = map['ed25519'] as String?;
                final x = map['x25519'] as String?;
                if (remoteId != null && ed != null && x != null && remoteId != nodeId) {
                  _peerCtrl.add(PeerInfo(
                    nodeId: remoteId,
                    ed25519PubKey: ed,
                    x25519PubKey: x,
                    alias: map['alias'] as String?,
                    transports: const ['nearby'],
                  ));
                }
              } catch (_) {}
              // Close ephemeral connection
              try { await Nearby().disconnectFromEndpoint(endid); } catch (_) {}
            },
            onPayloadTransferUpdate: (endid, update) {},
          );
        },
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
        serviceId: serviceId,
      );
    } catch (_) {
      // ignore advertising failure
    }
    // Start discovery of peers
    try {
      await Nearby().startDiscovery(
        nodeId,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, serviceIdStr) async {
          // Initiate a short connection to exchange hello metadata
          try {
            await Nearby().requestConnection(
              nodeId,
              id,
              onConnectionInitiated: (rid, infoData) async {
                await Nearby().acceptConnection(
                  rid,
                  onPayLoadRecieved: (endid, payload) async {
                    // We don't expect to receive here; we are the sender side.
                  },
                  onPayloadTransferUpdate: (endid, update) {},
                );
              },
              onConnectionResult: (rid, status) async {
                if (status == Status.CONNECTED) {
                  try {
                    await Nearby().sendBytesPayload(rid, Uint8List.fromList(utf8.encode(hello)));
                  } catch (_) {}
                  // Close connection shortly after
                  try { await Nearby().disconnectFromEndpoint(rid); } catch (_) {}
                }
              },
              onDisconnected: (rid) {},
            );
          } catch (_) {}
        },
        onEndpointLost: (id) {},
        serviceId: serviceId,
      );
    } catch (_) {
      // ignore discovery failure
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
    } catch (_) {}
    await _peerCtrl.close();
  }
}
