// Web implementation: exposes a postMessage-based API so external scripts
// can exercise the PeopleChain node from outside (same tab or other window).

// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../peoplechain_core/peoplechain_core.dart' as pc;

bool get jsApiSupported => true;

StreamSubscription<html.MessageEvent>? _sub;
pc.PeopleChainNode? _node;

void registerJsApi(pc.PeopleChainNode node) {
  _node = node;
  _sub?.cancel();
  _sub = html.window.onMessage.listen((event) async {
    try {
      final data = event.data;
      if (data is! Map) return; // Expect structured clone from postMessage with a Map-like object
      final type = data['target'];
      if (type != 'peoplechain') return;
      final id = data['id'];
      final method = data['method'] as String?;
      final params = (data['params'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

      Future<dynamic> run() async {
        final n = _node!;
        switch (method) {
          case 'getInfo':
            final info = await n.getNodeInfo();
            return {
              'nodeId': info.nodeId,
              'alias': info.alias,
              'ed25519': info.keys.ed25519,
              'x25519': info.keys.x25519,
              'tipHeight': info.tipHeight,
            };
          case 'recentPeers':
            final limit = (params['limit'] as num?)?.toInt() ?? 50;
            final peers = await n.recentPeers(limit: limit);
            return peers
                .map((p) => {
                      'nodeId': p.nodeId,
                      'alias': p.alias,
                      'ed25519': p.ed25519PubKey,
                      'x25519': p.x25519PubKey,
                      'lastSeenMs': p.lastSeenMs,
                      'transports': p.transports,
                    })
                .toList();
          case 'createOffer':
            return await n.createOfferPayload();
          case 'acceptOffer':
            final offer = params['offer'] as String?;
            if (offer == null) throw ArgumentError('offer required');
            return await n.acceptOfferAndCreateAnswer(offer);
          case 'acceptAnswer':
            final answer = params['answer'] as String?;
            if (answer == null) throw ArgumentError('answer required');
            await n.acceptAnswer(answer);
            return {'ok': true};
          case 'sendText':
            final to = params['toEd25519'] as String?;
            final text = params['text'] as String?;
            if (to == null || text == null) {
              throw ArgumentError('toEd25519 and text required');
            }
            final res = await n.sendMessage(toPubKey: to, text: text);
            return {'txId': res.txId, 'ok': res.ok, if (!res.ok && res.error != null) 'error': res.error};
          case 'getTx':
            final txId = params['txId'] as String?;
            if (txId == null) throw ArgumentError('txId required');
            final tx = await n.getTransactionById(txId);
            return tx?.toJson();
          case 'getMessages':
            final withPubKey = params['withPubKey'] as String?;
            final limit = (params['limit'] as num?)?.toInt();
            if (withPubKey == null) throw ArgumentError('withPubKey required');
            final msgs = await n.getMessages(withPubKey: withPubKey, limit: limit);
            return msgs.map((e) => e.toJson()).toList();
          case 'tipHeight':
            return await n.tipHeight();
          case 'getBlockByHeight':
            final h = (params['height'] as num?)?.toInt();
            if (h == null) throw ArgumentError('height required');
            final b = await n.getBlockByHeight(h);
            return b?.toJson();
          case 'getBlockById':
            final idStr = params['blockId'] as String?;
            if (idStr == null) throw ArgumentError('blockId required');
            final b2 = await n.getBlockById(idStr);
            return b2?.toJson();
          default:
            throw UnsupportedError('Unknown method: $method');
        }
      }

      dynamic result;
      try {
        result = await run();
        final resp = {'target': 'peoplechain', 'id': id, 'ok': true, 'result': result};
        // Prefer replying to the source window when available
        final src = event.source;
        if (src != null && src is html.WindowBase) {
          src.postMessage(resp, '*');
        } else {
          html.window.postMessage(resp, '*');
        }
      } catch (e) {
        final resp = {'target': 'peoplechain', 'id': id, 'ok': false, 'error': e.toString()};
        final src = event.source;
        if (src != null && src is html.WindowBase) {
          src.postMessage(resp, '*');
        } else {
          html.window.postMessage(resp, '*');
        }
      }
    } catch (_) {
      // ignore malformed events
    }
  });
}

void unregisterJsApi() {
  _sub?.cancel();
  _sub = null;
  _node = null;
}

Future<Map<String, dynamic>> sendTestPostMessage(Map<String, dynamic> request) async {
  final id = request['id'];
  final completer = Completer<Map<String, dynamic>>();
  late StreamSubscription<html.MessageEvent> sub;
  sub = html.window.onMessage.listen((event) {
    final d = event.data;
    if (d is Map && d['target'] == 'peoplechain' && d['id'] == id) {
      completer.complete(d.cast<String, dynamic>());
      sub.cancel();
    }
  });
  html.window.postMessage(request, '*');
  return completer.future.timeout(const Duration(seconds: 5));
}
