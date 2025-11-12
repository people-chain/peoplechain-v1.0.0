// No-op bootstrap for non-IO platforms (e.g., Web)

import '../../peoplechain_core.dart';

class MonitorServerHandle {
  final int port;
  final String host;
  const MonitorServerHandle._(this.host, this.port);
  Future<void> stop() async {}
}

class MonitorBootstrap {
  static Future<MonitorServerHandle?> start(PeopleChainNode node, {String host = '127.0.0.1', int port = 8080}) async {
    // Not supported on this platform
    return null;
  }
}
