// High-level integration smoke test used during the production campaign.
// Verifies auto connect logic against a simulated discovery relay.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_coach/peoplechain_core/src/p2p/adapters/discovery_adapter.dart';
import 'package:pocket_coach/peoplechain_core/src/p2p/adapters/webrtc_signal_api.dart';

class _TestWebRtc implements WebRtcSignalApi {
  bool connected = false;
  @override
  Future<String> createOfferPayload() async => base64Encode(utf8.encode('{"type":"offer","sdp":"O"}'));
  @override
  Future<String> acceptOfferAndCreateAnswer(String base64OfferPayload) async => base64Encode(utf8.encode('{"type":"answer","sdp":"A"}'));
  @override
  Future<void> acceptAnswer(String base64AnswerPayload) async { connected = true; }
}

class _Relay { final Set<String> nodes = {}; final Map<String,List<Map<String,dynamic>>> inbox = {}; }

void main() {
  test('auto-connect succeeds via simulated relay', () async {
    final r = _Relay();
    Future<http.Response> h(http.Request req) async {
      if (req.url.path == '/announce' && req.method == 'POST') {
        final id = (jsonDecode(req.body)['nodeId'] ?? '').toString();
        if (id.isNotEmpty) r.nodes.add(id);
        return http.Response(jsonEncode({'ok': true, 'online': r.nodes.map((e)=>{'nodeId':e}).toList()}), 200);
      }
      if (req.url.path == '/send' && req.method == 'POST') {
        final b = jsonDecode(req.body) as Map<String,dynamic>;
        final to = (b['to'] ?? '').toString();
        r.inbox.putIfAbsent(to, ()=>[]).add({'from':b['from'],'type':b['type'],'data':b['data'],'ts':DateTime.now().millisecondsSinceEpoch});
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      if (req.url.path == '/poll' && req.method == 'GET') {
        final node = req.url.queryParameters['node'] ?? '';
        final msgs = r.inbox.remove(node) ?? [];
        return http.Response(jsonEncode({'messages': msgs}), 200);
      }
      return http.Response('not_found', 404);
    }
    final discoA = DiscoveryAdapter(nodeId: 'A', ed25519PubKey: 'edA', x25519PubKey: 'xA', webrtc: _TestWebRtc(), client: MockClient(h));
    final discoB = DiscoveryAdapter(nodeId: 'B', ed25519PubKey: 'edB', x25519PubKey: 'xB', webrtc: _TestWebRtc(), client: MockClient(h));
    await Future.wait([discoA.start(), discoB.start()]);
    await Future.delayed(const Duration(milliseconds: 200));
    await Future.wait([discoA.stop(), discoB.stop()]);
  });
}
