abstract class IWebRtcAutoDiscovery {
  bool get isSupported;
  Future<void> start();
  Future<void> stop();
}
