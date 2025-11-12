import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

void main() {
  test('WebRTC QR payload encode/decode', () {
    final map = {
      'type': 'offer',
      'sdp': 'v=0...sdp',
      'nodeId': 'n123',
      'ed25519': 'edKey',
      'x25519': 'xKey',
      'alias': 'Alice',
    };
    final b64 = WebRtcQrPayload.encode(map);
    final out = WebRtcQrPayload.decode(b64);
    expect(out['type'], 'offer');
    expect(out['sdp'], 'v=0...sdp');
    expect(out['nodeId'], 'n123');
    expect(out['ed25519'], 'edKey');
    expect(out['x25519'], 'xKey');
    expect(out['alias'], 'Alice');
  });
}
