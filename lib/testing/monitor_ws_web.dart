import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

typedef MemoryCallback = void Function(int bytes);
typedef ErrorCallback = void Function(Object error);

class WebMonitorClient {
  final String url;
  final MemoryCallback onMemoryBytes;
  final ErrorCallback? onError;

  html.WebSocket? _ws;
  StreamSubscription<html.MessageEvent>? _msgSub;
  StreamSubscription<html.Event>? _errSub;
  StreamSubscription<html.Event>? _closeSub;

  WebMonitorClient({
    required this.url,
    required this.onMemoryBytes,
    this.onError,
  });

  void connect() {
    try {
      _ws?.close();
    } catch (_) {}
    _ws = html.WebSocket(url);
    _msgSub?.cancel();
    _errSub?.cancel();
    _closeSub?.cancel();

    _msgSub = _ws!.onMessage.listen((evt) {
      try {
        final data = evt.data;
        final String text = data is String ? data : (data?.toString() ?? '');
        if (text.isEmpty) return;
        final msg = jsonDecode(text);
        if (msg is Map) {
          final type = msg['type'];
          if (type == 'metric' && msg['metric'] == 'memory_bytes') {
            final v = msg['value'];
            if (v is num) onMemoryBytes(v.toInt());
          }
        }
      } catch (e) {
        onError?.call(e);
      }
    });
    _errSub = _ws!.onError.listen((_) => onError?.call('WebSocket error'));
    _closeSub = _ws!.onClose.listen((_) {});
  }

  void close() {
    try { _msgSub?.cancel(); } catch (_) {}
    try { _errSub?.cancel(); } catch (_) {}
    try { _closeSub?.cancel(); } catch (_) {}
    try { _ws?.close(); } catch (_) {}
    _ws = null;
  }
}
