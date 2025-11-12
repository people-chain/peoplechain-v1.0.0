import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

void main() {
  test('PeerStore put/get/recent', () async {
    final store = await IsarPeerStore.open(name: 'testpeers');
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.putOrUpdate(PeerRecord(
      nodeId: 'node-1',
      ed25519PubKey: 'ed1',
      x25519PubKey: 'x1',
      lastSeenMs: now - 1000,
      transports: const ['webrtc'],
      alias: 'Alice',
    ));
    await store.putOrUpdate(PeerRecord(
      nodeId: 'node-2',
      ed25519PubKey: 'ed2',
      x25519PubKey: 'x2',
      lastSeenMs: now,
      transports: const ['mdns'],
      alias: 'Bob',
    ));

    final p = await store.getByNodeId('node-1');
    expect(p, isNotNull);
    expect(p!.alias, 'Alice');

    final recent = await store.recent(limit: 10);
    expect(recent.first.nodeId, 'node-2');

    await store.markSeen('node-1', now + 1);
    final recent2 = await store.recent(limit: 10);
    expect(recent2.first.nodeId, 'node-1');
  });
}
