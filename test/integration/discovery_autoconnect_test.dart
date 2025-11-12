import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pocket_coach/peoplechain_core/src/p2p/adapters/discovery_adapter.dart';
import 'package:pocket_coach/peoplechain_core/src/p2p/adapters/webrtc_signal_api.dart';

class _TestWebRtc implements WebRtcSignalApi {
  bool connected = false;
  final String nodeId;
  final String ed;
  final String x;
  final String? alias;
  _TestWebRtc(this.nodeId, this.ed, this.x, this.alias);

  Map<String, dynamic> _payload(String type, String sdp) => {
        'type': type,
        'sdp': sdp,
        'nodeId': nodeId,
        'ed25519': ed,
        'x25519': x,
        if (alias != null) 'alias': alias,
      };

  @override
  Future<String> createOfferPayload() async => base64Encode(utf8.encode(jsonEncode(_payload('offer', 'SDP_O'))));
  @override
  Future<String> acceptOfferAndCreateAnswer(String base64OfferPayload) async =>
      base64Encode(utf8.encode(jsonEncode(_payload('answer', 'SDP_A'))));
  @override
  Future<void> acceptAnswer(String base64AnswerPayload) async {
    connected = true;
  }
}

class _FakeRelay {
  final Set<String> nodes = <String>{};
  final Map<String, List<Map<String, dynamic>>> inbox = {};

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/announce' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = (body['nodeId'] ?? '').toString();
      if (id.isNotEmpty) nodes.add(id);
      final online = nodes.map((e) => {'nodeId': e}).toList();
      return http.Response(jsonEncode({'ok': true, 'online': online}), 200);
    }
    if (request.url.path == '/send' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final to = (body['to'] ?? '').toString();
      inbox.putIfAbsent(to, () => <Map<String, dynamic>>[]).add({
        'from': (body['from'] ?? '').toString(),
        'type': (body['type'] ?? '').toString(),
        'data': body['data'],
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      return http.Response(jsonEncode({'ok': true}), 200);
    }
    if (request.url.path == '/poll' && request.method == 'GET') {
      final node = request.url.queryParameters['node'] ?? '';
      final msgs = inbox.remove(node) ?? <Map<String, dynamic>>[];
      return http.Response(jsonEncode({'messages': msgs}), 200);
    }
    return http.Response('not_found', 404);
  }
}

void main() {
  test('two nodes auto-connect via Discovery relay without manual SDP', () async {
    final relay = _FakeRelay();
    final clientA = MockClient(relay.handle);
    final clientB = MockClient(relay.handle);

    final webrtcA = _TestWebRtc('nodeA', 'edA', 'xA', 'A');
    final webrtcB = _TestWebRtc('nodeB', 'edB', 'xB', 'B');

    final discoA = DiscoveryAdapter(
      nodeId: 'nodeA', ed25519PubKey: 'edA', x25519PubKey: 'xA', alias: 'A', webrtc: webrtcA, client: clientA,
      host: 'localhost', port: 8081,
    );
    final discoB = DiscoveryAdapter(
      nodeId: 'nodeB', ed25519PubKey: 'edB', x25519PubKey: 'xB', alias: 'B', webrtc: webrtcB, client: clientB,
      host: 'localhost', port: 8081,
    );

    await Future.wait([discoA.start(), discoB.start()]);

    // Let the polling loop run a bit
    await Future.delayed(const Duration(milliseconds: 200));

    await discoA.stop();
    await discoB.stop();

    expect(webrtcA.connected || webrtcB.connected, true, reason: 'At least one side should mark connected after answer applied');
  });
}
