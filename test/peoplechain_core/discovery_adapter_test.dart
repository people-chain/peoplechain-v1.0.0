import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pocket_coach/peoplechain_core/src/p2p/adapters/discovery_adapter.dart';
import 'package:pocket_coach/peoplechain_core/src/p2p/adapters/webrtc_signal_api.dart';

class _TestWebRtc implements WebRtcSignalApi {
  String? lastOfferAccepted;
  String? lastAnswerAccepted;
  int offersCreated = 0;
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
  Future<String> createOfferPayload() async {
    offersCreated += 1;
    return base64Encode(utf8.encode(jsonEncode(_payload('offer', 'OFFER_SDP'))));
  }

  @override
  Future<String> acceptOfferAndCreateAnswer(String base64OfferPayload) async {
    lastOfferAccepted = base64OfferPayload;
    return base64Encode(utf8.encode(jsonEncode(_payload('answer', 'ANSWER_SDP'))));
  }

  @override
  Future<void> acceptAnswer(String base64AnswerPayload) async {
    lastAnswerAccepted = base64AnswerPayload;
  }
}

void main() {
  group('DiscoveryAdapter', () {
    test('announces and sends offer to online peer', () async {
      // Fake server that returns peerB online and accepts /send
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/announce' && request.method == 'POST') {
          return http.Response(jsonEncode({
            'ok': true,
            'online': [
              {'nodeId': 'nodeA'},
              {'nodeId': 'nodeB'},
            ]
          }), 200);
        }
        if (request.url.path == '/send' && request.method == 'POST') {
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (request.url.path == '/poll' && request.method == 'GET') {
          return http.Response(jsonEncode({'messages': []}), 200);
        }
        return http.Response('not_found', 404);
      });

      final webrtc = _TestWebRtc('nodeA', 'edA', 'xA', 'A');
      final disco = DiscoveryAdapter(
        nodeId: 'nodeA',
        ed25519PubKey: 'edA',
        x25519PubKey: 'xA',
        webrtc: webrtc,
        alias: 'A',
        client: client,
        host: 'localhost',
        port: 8081,
      );

      await disco.start();

      // Allow async tasks to run
      await Future.delayed(const Duration(milliseconds: 50));

      // Should have posted /send with an offer to nodeB
      final sent = requests.where((r) => r.url.path == '/send').toList();
      expect(sent.isNotEmpty, true);
      final body = jsonDecode(sent.first.body as String) as Map<String, dynamic>;
      expect(body['type'], 'offer');
      expect(body['to'], 'nodeB');

      await disco.stop();
    });

    test('receives offer via poll and replies with answer', () async {
      // Queue one offer in /poll for nodeB and observe /send answer
      bool answered = false;
      final webrtcB = _TestWebRtc('nodeB', 'edB', 'xB', 'B');
      final client = MockClient((request) async {
        if (request.url.path == '/announce' && request.method == 'POST') {
          return http.Response(jsonEncode({'ok': true, 'online': []}), 200);
        }
        if (request.url.path == '/poll' && request.method == 'GET') {
          final messages = [
            {
              'from': 'nodeA',
              'type': 'offer',
              'data': await webrtcB.createOfferPayload(), // just a base64 blob shape
              'ts': DateTime.now().millisecondsSinceEpoch
            }
          ];
          return http.Response(jsonEncode({'messages': messages}), 200);
        }
        if (request.url.path == '/send' && request.method == 'POST') {
          final j = jsonDecode(request.body) as Map<String, dynamic>;
          if (j['type'] == 'answer') {
            answered = true;
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response('not_found', 404);
      });

      final discoB = DiscoveryAdapter(
        nodeId: 'nodeB',
        ed25519PubKey: 'edB',
        x25519PubKey: 'xB',
        webrtc: webrtcB,
        alias: 'B',
        client: client,
        host: 'localhost',
        port: 8081,
      );
      // Run only one polling loop iteration by starting then stopping shortly after
      unawaited(discoB.start());
      await Future.delayed(const Duration(milliseconds: 50));
      await discoB.stop();
      expect(answered, true);
    });
  });
}
