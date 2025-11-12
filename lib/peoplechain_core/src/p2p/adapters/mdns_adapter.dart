import 'dart:async';
import 'dart:convert';
import 'dart:io' show RawDatagramSocket;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:multicast_dns/multicast_dns.dart';

import '../p2p_manager.dart';

class MdnsAdapter implements P2PAdapter {
  static const String service = '_peoplechain._udp';

  final String nodeId;
  final String ed25519PubKey;
  final String x25519PubKey;
  final String? alias;

  MDnsClient? _client;
  bool _running = false;
  final _peerCtrl = StreamController<PeerInfo>.broadcast();

  MdnsAdapter({required this.nodeId, required this.ed25519PubKey, required this.x25519PubKey, this.alias});

  @override
  bool get isSupported => !kIsWeb; // mDNS not available on Flutter web

  @override
  Stream<PeerInfo> onPeerDiscovered() => _peerCtrl.stream;

  @override
  Future<void> start() async {
    if (!isSupported || _running) return;
    _running = true;
    _client = MDnsClient(rawDatagramSocketFactory: (host, port, {reuseAddress = true, reusePort = false, ttl = 255}) {
      return RawDatagramSocket.bind(host, port, reuseAddress: true, ttl: ttl);
    });
    await _client!.start();

    // Announce via PTR + SRV + TXT using hostname as nodeId.local
    // Note: multicast_dns package primarily supports discovery. For announce, many apps rely on platform services.
    // We'll at least browse and parse others; advertising can be implemented via native later.

    // Browse peers
    _browse();
  }

  void _browse() async {
    final client = _client;
    if (client == null) return;
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(service))) {
      await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
        await for (final TxtResourceRecord txt in client.lookup<TxtResourceRecord>(ResourceRecordQuery.text(ptr.domainName))) {
          final dynamic raw = txt.text;
          final List<String> txts = raw is List<String> ? raw : [raw?.toString() ?? ''];
          final map = _parseTxt(txts); // key=value pairs
          final id = map['nodeId'];
          final ed = map['ed25519'];
          final x = map['x25519'];
          if (id != null && ed != null && x != null && id != nodeId) {
            _peerCtrl.add(PeerInfo(
              nodeId: id,
              ed25519PubKey: ed,
              x25519PubKey: x,
              alias: map['alias'],
              transports: const ['mdns'],
            ));
          }
        }
      }
    }
  }

  Map<String, String> _parseTxt(List<String> txts) {
    final map = <String, String>{};
    for (final e in txts) {
      final i = e.indexOf('=');
      if (i > 0) {
        final k = e.substring(0, i);
        final v = e.substring(i + 1);
        map[k] = v;
      }
    }
    return map;
  }

  @override
  Future<void> stop() async {
    _running = false;
    _client?.stop();
    await _peerCtrl.close();
    _client = null;
  }
}
