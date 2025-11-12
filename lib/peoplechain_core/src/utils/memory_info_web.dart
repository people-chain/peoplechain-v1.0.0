// Web JS heap memory via window.performance.memory (non-standard but widely available in Chromium)
// Falls back to null if not available.
// This file is conditionally imported only on web (dart.library.html).
import 'dart:html' as html;

Future<int?> getResidentMemoryBytes() async {
  try {
    final anyPerf = html.window.performance as dynamic;
    final mem = anyPerf.memory; // may be null or throw
    if (mem == null) return null;
    final used = mem.usedJSHeapSize as num?;
    if (used == null) return null;
    return used.toInt();
  } catch (_) {
    return null;
  }
}
