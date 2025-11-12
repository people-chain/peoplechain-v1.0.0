import 'dart:io';

Future<int?> getResidentMemoryBytes() async {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return null;
  }
}
