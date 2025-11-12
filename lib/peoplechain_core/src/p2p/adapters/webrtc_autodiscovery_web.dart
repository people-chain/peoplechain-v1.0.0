// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

import 'webrtc_autodiscovery_interface.dart';
import 'webrtc_adapter.dart';

class WebRtcBroadcastAutoDiscovery implements IWebRtcAutoDiscovery {
  final WebRtcAdapter adapter;
  final String channelName;
  final Duration retryInterval;

  html.BroadcastChannel? _channel;
  StreamSubscription<html.MessageEvent>? _sub;
  Timer? _timer;
  bool _running = false;
  bool _answered = false;

  WebRtcBroadcastAutoDiscovery(
    this.adapter, {
    this.channelName = 'peoplechain-webrtc',
    this.retryInterval = const Duration(seconds: 7),
  });

  @override
  bool get isSupported => true;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _channel = html.BroadcastChannel(channelName);
    _sub = _channel!.onMessage.listen((event) async {
      try {
        final data = event.data;
        if (data is! Map) return;
        final map = data.cast<String, dynamic>();
        final type = map['type'] as String?;
        if (type == 'offer') {
          if ((map['from'] as String?) == adapter.nodeId) return;
          final offerPayload = map['payload'] as String?;
          if (offerPayload == null) return;
          final answer = await adapter.acceptOfferAndCreateAnswer(offerPayload);
          final resp = <String, dynamic>{
            'type': 'answer',
            'from': adapter.nodeId,
            'to': map['from'],
            'payload': answer,
          };
          _channel!.postMessage(resp);
        } else if (type == 'answer') {
          if (map['to'] != adapter.nodeId) return;
          final ans = map['payload'] as String?;
          if (ans == null) return;
          if (!_answered) {
            _answered = true;
            await adapter.acceptAnswer(ans);
          }
        }
      } catch (_) {}
    });

    _timer = Timer.periodic(retryInterval, (_) async {
      if (adapter.isOpen) return;
      try {
        final offer = await adapter.createOfferPayload();
        final msg = <String, dynamic>{'type': 'offer', 'from': adapter.nodeId, 'payload': offer};
        _channel!.postMessage(msg);
      } catch (_) {}
    });
  }

  @override
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      _channel?.close();
    } catch (_) {}
    _channel = null;
  }
}
