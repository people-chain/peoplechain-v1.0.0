import 'dart:async';

enum LogLevel { info, warning, error }

class LogEntry {
  final DateTime ts;
  final LogLevel level;
  final String message;
  LogEntry({required this.ts, required this.level, required this.message});
}

class MetricsPoint {
  final DateTime ts;
  final double value;
  MetricsPoint(this.ts, this.value);
}

class MetricsBus {
  static final MetricsBus I = MetricsBus._();
  MetricsBus._();

  // Streams
  final _latencyCtrl = StreamController<MetricsPoint>.broadcast();
  final _handshakeCtrl = StreamController<MetricsPoint>.broadcast();
  // Detailed handshake metrics
  final _hsRttCtrl = StreamController<MetricsPoint>.broadcast();
  final _hsIceCtrl = StreamController<MetricsPoint>.broadcast();
  final _hsConnCtrl = StreamController<MetricsPoint>.broadcast();
  final _cpuCtrl = StreamController<MetricsPoint>.broadcast();
  final _memCtrl = StreamController<MetricsPoint>.broadcast();
  final _stabilityCtrl = StreamController<MetricsPoint>.broadcast();
  final _logsCtrl = StreamController<LogEntry>.broadcast();
  // Network throughput (bytes)
  final _netUpCtrl = StreamController<MetricsPoint>.broadcast();
  final _netDownCtrl = StreamController<MetricsPoint>.broadcast();

  Stream<MetricsPoint> latency() => _latencyCtrl.stream;
  Stream<MetricsPoint> handshake() => _handshakeCtrl.stream;
  Stream<MetricsPoint> handshakeRtt() => _hsRttCtrl.stream;
  Stream<MetricsPoint> iceSetup() => _hsIceCtrl.stream;
  Stream<MetricsPoint> connectionTime() => _hsConnCtrl.stream;
  Stream<MetricsPoint> cpu() => _cpuCtrl.stream;
  Stream<MetricsPoint> memory() => _memCtrl.stream;
  Stream<MetricsPoint> stability() => _stabilityCtrl.stream;
  Stream<LogEntry> logs() => _logsCtrl.stream;
  Stream<MetricsPoint> netUp() => _netUpCtrl.stream;
  Stream<MetricsPoint> netDown() => _netDownCtrl.stream;

  void recordLatency(Duration d) {
    _latencyCtrl.add(MetricsPoint(DateTime.now(), d.inMilliseconds.toDouble()));
  }

  void recordHandshake(Duration d) {
    _handshakeCtrl.add(MetricsPoint(DateTime.now(), d.inMilliseconds.toDouble()));
  }

  void recordHandshakeRtt(Duration d) {
    _hsRttCtrl.add(MetricsPoint(DateTime.now(), d.inMilliseconds.toDouble()));
  }

  void recordIceSetup(Duration d) {
    _hsIceCtrl.add(MetricsPoint(DateTime.now(), d.inMilliseconds.toDouble()));
  }

  void recordConnectionTime(Duration d) {
    _hsConnCtrl.add(MetricsPoint(DateTime.now(), d.inMilliseconds.toDouble()));
  }

  void recordCpu(double pct) {
    _cpuCtrl.add(MetricsPoint(DateTime.now(), pct));
  }

  void recordMemoryBytes(int bytes) {
    _memCtrl.add(MetricsPoint(DateTime.now(), bytes.toDouble()));
  }

  void recordStability(double score) {
    _stabilityCtrl.add(MetricsPoint(DateTime.now(), score));
  }

   // Record raw byte counters; consumers can aggregate per second.
  void recordNetUpBytes(int bytes) {
    if (bytes <= 0) return;
    _netUpCtrl.add(MetricsPoint(DateTime.now(), bytes.toDouble()));
  }

  void recordNetDownBytes(int bytes) {
    if (bytes <= 0) return;
    _netDownCtrl.add(MetricsPoint(DateTime.now(), bytes.toDouble()));
  }

  void logInfo(String msg) => _logsCtrl.add(LogEntry(ts: DateTime.now(), level: LogLevel.info, message: msg));
  void logWarn(String msg) => _logsCtrl.add(LogEntry(ts: DateTime.now(), level: LogLevel.warning, message: msg));
  void logError(String msg) => _logsCtrl.add(LogEntry(ts: DateTime.now(), level: LogLevel.error, message: msg));

  void dispose() {
    _latencyCtrl.close();
    _handshakeCtrl.close();
    _hsRttCtrl.close();
    _hsIceCtrl.close();
    _hsConnCtrl.close();
    _cpuCtrl.close();
    _memCtrl.close();
    _stabilityCtrl.close();
    _logsCtrl.close();
    _netUpCtrl.close();
    _netDownCtrl.close();
  }
}

/// Utility to capture print() output within a zone and forward to MetricsBus logs.
Future<T> capturePrints<T>(Future<T> Function() body) async {
  return await runZoned(body, zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      MetricsBus.I.logInfo(line);
      parent.print(zone, line);
    },
  ));
}
