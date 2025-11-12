import 'webrtc_autodiscovery_interface.dart';
import 'webrtc_adapter.dart';

class WebRtcBroadcastAutoDiscovery implements IWebRtcAutoDiscovery {
  WebRtcBroadcastAutoDiscovery(WebRtcAdapter adapter, {String channelName = 'peoplechain-webrtc', Duration retryInterval = const Duration(seconds: 7)});

  @override
  bool get isSupported => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
