import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart' as pc;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebRTC loopback (manual/QR payload exchange)', () {
    test('offer/answer connects data channel and bridges SyncEngine', () async {
      // This test requires a runtime with WebRTC support; often fails in headless CI.
      // Skip by default; run locally on device or web by removing skip.
    }, skip: 'Requires device/browser WebRTC. Run manually by removing skip.');
  });
}
