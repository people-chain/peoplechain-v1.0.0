// Fallback for platforms without dart:io or unsupported memory query
Future<int?> getResidentMemoryBytes() async => null;
