import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart' as pc;

void main() {
  group('Tx pipeline (M3)', () {
    late pc.InMemoryMessageDb db;
    late pc.CryptoManager aliceCrypto;
    late pc.CryptoManager bobCrypto;

    setUp(() async {
      db = pc.InMemoryMessageDb();
      aliceCrypto = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
      bobCrypto = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
      await aliceCrypto.generateAndStoreKeys();
      await bobCrypto.generateAndStoreKeys();
    });

    test('createTextTx signs deterministically and stored in DB', () async {
      final aliceDesc = await aliceCrypto.getDescriptor();
      final bobDesc = await bobCrypto.getDescriptor();
      expect(aliceDesc, isNotNull);
      expect(bobDesc, isNotNull);

      final builder = pc.TxBuilder(crypto: aliceCrypto, db: db);
      final tx = await builder.createTextTx(toEd25519: bobDesc!.publicIdentity.ed25519, text: 'Hello');
      expect(tx.payload.type, 'text');
      expect(tx.payload.text, 'Hello');
      // Verify signature
      final body = _canonicalBody(tx);
      final ok = await aliceCrypto.verify(
        message: body,
        signature: pc.b64urlDecode(tx.signature),
        publicKey: pc.b64urlDecode(aliceDesc!.publicIdentity.ed25519),
      );
      expect(ok, isTrue);
      final stored = await db.getTransaction(tx.txId);
      expect(stored, isNotNull);
    });

    test('createMediaTx produces encrypted chunks and manifest, recoverable by recipient', () async {
      final aliceDesc = await aliceCrypto.getDescriptor();
      final bobDesc = await bobCrypto.getDescriptor();
      final builder = pc.TxBuilder(crypto: aliceCrypto, db: db);
      // Prepare 1MiB random data
      final data = Uint8List.fromList(List<int>.generate(1024 * 1024, (i) => i % 256));
      final tx = await builder.createMediaTx(
        toEd25519: bobDesc!.publicIdentity.ed25519,
        toX25519: bobDesc.publicIdentity.x25519,
        bytes: data,
        mime: 'application/octet-stream',
        chunkSize: 200 * 1024,
      );
      expect(tx.payload.type, 'media');
      expect(tx.payload.chunkRef, isNotNull);

      // Retrieve manifest chunk
      final manifestChunk = await db.getChunk(tx.payload.chunkRef!);
      expect(manifestChunk, isNotNull);
      expect(manifestChunk!.data, isNotNull);

      // Bob decrypts manifest
      final codec = pc.ChunkCodec();
      final shared = await bobCrypto.sharedSecret(pc.b64urlDecode(aliceDesc!.publicIdentity.x25519));
      final participantsKey = _participantsKey(aliceDesc.publicIdentity.x25519, bobDesc.publicIdentity.x25519);
      final manifestPlain = await codec.decrypt(
        encoded: manifestChunk.data!,
        sharedSecret: shared,
        participantsKey: participantsKey,
      );
      final manifestJson = String.fromCharCodes(manifestPlain);
      expect(manifestJson.contains('"chunks"'), isTrue);

      // Parse manifest and decrypt first data chunk
      final manifest = _readManifest(manifestJson);
      expect(manifest.totalSize, data.length);
      expect(manifest.chunks.isNotEmpty, isTrue);
      final firstId = manifest.chunks.first.id;
      final firstChunk = await db.getChunk(firstId);
      expect(firstChunk, isNotNull);
      final firstPlain = await codec.decrypt(
        encoded: firstChunk!.data!,
        sharedSecret: shared,
        participantsKey: participantsKey,
      );
      // Compare with original slice
      expect(firstPlain, data.sublist(0, firstPlain.length));
    });
  });
}

Uint8List _canonicalBody(pc.TxModel tx) {
  final map = <String, dynamic>{
    'from': tx.from,
    'to': tx.to,
    'nonce': tx.nonce,
    'timestamp_ms': tx.timestampMs,
    'payload': tx.payload.toJson(),
  };
  return Uint8List.fromList(const Utf8Encoder().convert(jsonEncode(map)));
}

String _participantsKey(String a, String b) => a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

_Manifest _readManifest(String s) {
  final map = jsonDecode(s) as Map<String, dynamic>;
  final totalSize = map['total_size'] as int;
  final chunks = (map['chunks'] as List)
      .map((e) => _ManifestChunk(id: e['id'] as String, size: e['size'] as int))
      .toList();
  return _Manifest(totalSize: totalSize, chunks: chunks);
}

class _Manifest {
  final int totalSize;
  final List<_ManifestChunk> chunks;
  _Manifest({required this.totalSize, required this.chunks});
}

class _ManifestChunk {
  final String id;
  final int size;
  _ManifestChunk({required this.id, required this.size});
}
