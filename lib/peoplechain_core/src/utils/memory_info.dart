import './memory_info_stub.dart'
    if (dart.library.io) './memory_info_io.dart'
    if (dart.library.html) './memory_info_web.dart' as impl;

/// Returns current resident memory in bytes if available on this platform, otherwise null.
Future<int?> getResidentMemoryBytes() async {
  return impl.getResidentMemoryBytes();
}
