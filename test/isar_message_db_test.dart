import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart' as pc;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IsarMessageDb', () {
    late pc.IsarMessageDb db;

    setUpAll(() async {
      db = await pc.IsarMessageDb.open(name: 'pc_test_isar');
    });

    tearDownAll(() async {
      await db.close();
    });

    test('stores and retrieves chunks', () async {
      final c = pc.ChunkModel(
        chunkId: 'ci1',
        type: 'text',
        sizeBytes: 5,
        hash: 'h-1',
      );
      await db.putChunk(c);
      final got = await db.getChunk('ci1');
      expect(got?.hash, 'h-1');
    });

    test('stores and queries transactions by conversation', () async {
      final tx1 = pc.TxModel(
        txId: 'ti1',
        from: 'A',
        to: 'B',
        nonce: 1,
        timestampMs: 10,
        payload: const pc.TxPayloadModel(type: 'text', text: 'hi'),
        signature: 'sig',
      );
      final tx2 = pc.TxModel(
        txId: 'ti2',
        from: 'B',
        to: 'A',
        nonce: 2,
        timestampMs: 20,
        payload: const pc.TxPayloadModel(type: 'text', text: 'yo'),
        signature: 'sig',
      );
      await db.putTransaction(tx1);
      await db.putTransaction(tx2);
      final convo = await db.getConversation(a: 'A', b: 'B');
      expect(convo.length, 2);
      expect(convo.first.txId, 'ti1');
      expect(convo.last.txId, 'ti2');
    });

    test('stores and retrieves blocks by id and height', () async {
      final header = pc.BlockHeaderModel(
        blockId: 'bi1',
        height: 0,
        prevBlockId: '0x0',
        timestampMs: 1000,
        txMerkleRoot: 'root',
        proposer: 'A',
      );
      final b = pc.BlockModel(header: header, txIds: const [], signatures: const []);
      await db.putBlock(b);
      expect((await db.getBlockById('bi1'))?.header.height, 0);
      expect((await db.getBlockByHeight(0))?.header.blockId, 'bi1');
      expect(await db.tipHeight(), 0);
    });
  });
}
