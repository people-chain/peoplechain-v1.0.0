// IO bootstrap to start the local monitor server alongside the node.

import 'dart:io';

import '../../peoplechain_core.dart';
import '../../../testing/metrics_bus.dart';
import 'node_monitor_server.dart';

class MonitorServerHandle {
  final NodeMonitorServer _server;
  final String host;
  final int port;
  MonitorServerHandle._(this._server, this.host, this.port);
  Future<void> stop() async => _server.stop();
}

class MonitorBootstrap {
  static Future<MonitorServerHandle?> start(
    PeopleChainNode node, {
    String host = '127.0.0.1',
    int port = 8080,
  }) async {
    // Allow overrides via both --dart-define and environment variables.
    // --dart-define takes precedence when provided.
    // Note: Using String.fromEnvironment allows reliable overrides when running via flutter run/build.
    const ddPortStr = String.fromEnvironment('PEOPLECHAIN_MONITOR_PORT');
    const ddLanStr = String.fromEnvironment('PEOPLECHAIN_MONITOR_LAN');
    final ddPort = int.tryParse(ddPortStr);
    final ddLan = (ddLanStr.isNotEmpty ? ddLanStr : '0') == '1';

    final env = Platform.environment;
    final envPort = int.tryParse(env['PEOPLECHAIN_MONITOR_PORT'] ?? '');
    final envLan = (env['PEOPLECHAIN_MONITOR_LAN'] ?? '0') == '1';

    final exposeLan = ddLan || envLan;
    final bindHost = exposeLan ? '0.0.0.0' : host;
    final bindPort = ddPort ?? envPort ?? port;

    final srv = NodeMonitorServer(node: node);
    try {
      MetricsBus.I.logInfo('[Monitor] Starting NodeMonitorServer on $bindHost:$bindPort');
      stdout.writeln('[Monitor] Starting NodeMonitorServer on $bindHost:$bindPort');
      await srv.start(host: bindHost, port: bindPort);
      MetricsBus.I.logInfo('[Monitor] NodeMonitorServer listening on http://$bindHost:$bindPort');
      stdout.writeln('[Monitor] NodeMonitorServer listening on http://$bindHost:$bindPort');
      return MonitorServerHandle._(srv, bindHost, bindPort);
    } on SocketException catch (e) {
      // If the port is in use, provide a clearer hint and do not crash the app startup.
      final msg = '[Monitor] Failed to bind $bindHost:$bindPort (${e.osError?.message ?? e.message}). ' 
          'You can set a different port with --dart-define=PEOPLECHAIN_MONITOR_PORT=PORT or environment.';
      MetricsBus.I.logError(msg);
      stderr.writeln(msg);
      rethrow;
    } catch (e) {
      final msg = '[Monitor] Failed to start monitor server: $e';
      MetricsBus.I.logError(msg);
      stderr.writeln(msg);
      rethrow;
    }
  }
}
