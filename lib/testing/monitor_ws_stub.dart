// Stub client for non-web platforms.

typedef MemoryCallback = void Function(int bytes);
typedef ErrorCallback = void Function(Object error);

class WebMonitorClient {
  final String url;
  final MemoryCallback onMemoryBytes;
  final ErrorCallback? onError;
  WebMonitorClient({required this.url, required this.onMemoryBytes, this.onError});
  void connect() {}
  void close() {}
}
