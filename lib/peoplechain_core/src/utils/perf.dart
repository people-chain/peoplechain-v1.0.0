import 'dart:math';

/// Simple performance recorder for latency/throughput style measurements.
class PerfRecorder {
  final Map<String, _Metric> _metrics = {};

  void record(String name, Duration duration, {int bytes = 0}) {
    final m = _metrics.putIfAbsent(name, () => _Metric(name));
    m.add(duration, bytes: bytes);
  }

  PerfReport report({bool reset = false}) {
    final items = <PerfItem>[];
    for (final m in _metrics.values) {
      items.add(m.toItem());
    }
    if (reset) {
      _metrics.clear();
    }
    return PerfReport(items: items);
  }
}

class PerfReport {
  final List<PerfItem> items;
  const PerfReport({required this.items});

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(growable: false),
      };

  @override
  String toString() => toJson().toString();
}

class PerfItem {
  final String name;
  final int count;
  final int totalMs;
  final double avgMs;
  final int minMs;
  final int maxMs;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final int totalBytes;
  final double msgPerSec; // estimated throughput
  final double bytesPerSec; // estimated throughput

  const PerfItem({
    required this.name,
    required this.count,
    required this.totalMs,
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.totalBytes,
    required this.msgPerSec,
    required this.bytesPerSec,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'count': count,
        'total_ms': totalMs,
        'avg_ms': avgMs,
        'min_ms': minMs,
        'max_ms': maxMs,
        'p50_ms': p50Ms,
        'p95_ms': p95Ms,
        'p99_ms': p99Ms,
        'total_bytes': totalBytes,
        'msg_per_sec': msgPerSec,
        'bytes_per_sec': bytesPerSec,
      };
}

class _Metric {
  final String name;
  final List<int> _durMs = [];
  int _totalBytes = 0;

  _Metric(this.name);

  void add(Duration d, {int bytes = 0}) {
    _durMs.add(d.inMilliseconds);
    _totalBytes += bytes;
  }

  PerfItem toItem() {
    if (_durMs.isEmpty) {
      return const PerfItem(
        name: 'empty',
        count: 0,
        totalMs: 0,
        avgMs: 0,
        minMs: 0,
        maxMs: 0,
        p50Ms: 0,
        p95Ms: 0,
        p99Ms: 0,
        totalBytes: 0,
        msgPerSec: 0,
        bytesPerSec: 0,
      );
    }
    _durMs.sort();
    final count = _durMs.length;
    final totalMs = _durMs.fold<int>(0, (a, b) => a + b);
    final double avgMs = totalMs / count;
    final minMs = _durMs.first;
    final maxMs = _durMs.last;
    double pct(double p) {
      final idx = max(0, min(count - 1, ((p / 100.0) * (count - 1)).round()));
      return _durMs[idx].toDouble();
    }
    final p50 = pct(50);
    final p95 = pct(95);
    final p99 = pct(99);
    final seconds = totalMs / 1000.0;
    final double msgPerSec = seconds > 0 ? count / seconds : 0.0;
    final double bytesPerSec = seconds > 0 ? _totalBytes / seconds : 0.0;
    return PerfItem(
      name: name,
      count: count,
      totalMs: totalMs,
      avgMs: avgMs,
      minMs: minMs,
      maxMs: maxMs,
      p50Ms: p50,
      p95Ms: p95,
      p99Ms: p99,
      totalBytes: _totalBytes,
      msgPerSec: msgPerSec,
      bytesPerSec: bytesPerSec,
    );
  }
}
