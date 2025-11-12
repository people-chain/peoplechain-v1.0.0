import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';
import 'package:cryptography/cryptography.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Future<String> _merkle(List<String> ids) async {
  if (ids.isEmpty) return '';
  var layer = [for (final id in ids) _utf8(id)];
  final sha = Sha256();
  while (layer.length > 1) {
    final next = <Uint8List>[];
    for (var i = 0; i < layer.length; i += 2) {
      final left = layer[i];
      final right = i + 1 < layer.length ? layer[i + 1] : left;
      final h = await sha.hash(<int>[...left, ...right]);
      next.add(Uint8List.fromList(h.bytes));
    }
    layer = next;
  }
  final root = await sha.hash(layer.first);
  return base64UrlEncode(root.bytes).replaceAll('=', '');
}

void main() {
  group('SyncEngine', () {
    test('two peers sync blocks and txs over in-memory transport', () async {
      // DBs
      final dbA = InMemoryMessageDb();
      final dbB = InMemoryMessageDb();

      // Crypto with in-memory storage
      final storageA = KeyStorage(driver: InMemorySecureStorageDriver());
      final storageB = KeyStorage(driver: InMemorySecureStorageDriver());
      final cryptoA = CryptoManager(storage: storageA);
      final cryptoB = CryptoManager(storage: storageB);
      await cryptoA.generateAndStoreKeys();
      await cryptoB.generateAndStoreKeys();

      // Build some txs on A
      final descB = await cryptoB.getDescriptor();
      final descA = await cryptoA.getDescriptor();
      expect(descA, isNotNull);
      expect(descB, isNotNull);
      final txbA = TxBuilder(crypto: cryptoA, db: dbA);
      final t1 = await txbA.createTextTx(toEd25519: descB!.publicIdentity.ed25519, text: 'hi');
      final t2 = await txbA.createTextTx(toEd25519: descB.publicIdentity.ed25519, text: 'there');

      // Build genesis and one block referencing t1,t2
      final genesis = BlockModel(
        header: BlockHeaderModel(
          blockId: 'genesis',
          height: 0,
          prevBlockId: '',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          txMerkleRoot: '',
          proposer: descA!.publicIdentity.ed25519,
        ),
        txIds: const [],
        signatures: const [],
      );
      await dbA.putBlock(genesis);
      final merkle = await _merkle([t1.txId, t2.txId]);
      final b1 = BlockModel(
        header: BlockHeaderModel(
          blockId: 'b1',
          height: 1,
          prevBlockId: genesis.header.blockId,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          txMerkleRoot: merkle,
          proposer: descA.publicIdentity.ed25519,
        ),
        txIds: [t1.txId, t2.txId],
        signatures: const [],
      );
      await dbA.putBlock(b1);

      // Transports
      final ta = InMemoryPipeTransport();
      final tb = InMemoryPipeTransport();
      ta.linkPeer(tb);
      tb.linkPeer(ta);

      // Engines
      final engA = SyncEngine(db: dbA, crypto: cryptoA, transport: ta);
      final engB = SyncEngine(db: dbB, crypto: cryptoB, transport: tb);
      await engA.start();
      await engB.start();

      // Open channels
      ta.open();
      tb.open();

      // Allow time for exchange
      await Future.delayed(const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 200));

      // Verify B synced
      final tipB = await dbB.tipHeight();
      expect(tipB, 1);
      final got1 = await dbB.getTransaction(t1.txId);
      final got2 = await dbB.getTransaction(t2.txId);
      expect(got1, isNotNull);
      expect(got2, isNotNull);

      await engA.stop();
      await engB.stop();
    });
  });
}
