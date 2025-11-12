import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart' as pc;

import 'package:pocket_coach/peoplechain_core/src/tx/chunk_codec.dart' as codec;
import 'package:pocket_coach/peoplechain_core/src/utils/perf.dart';
import 'package:pocket_coach/peoplechain_core/src/utils/memory_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stress: 100 media uploads (A -> B) with decrypt verification', () {
    late pc.IsarMessageDb dbA;
    late pc.IsarMessageDb dbB;
    late pc.CryptoManager cryptoA;
    late pc.CryptoManager cryptoB;
    late pc.SyncEngine syncA;
    late pc.SyncEngine syncB;
    final recorder = PerfRecorder();

    setUpAll(() async {
      dbA = await pc.IsarMessageDb.open(name: 'pc_stress_media_a');
      dbB = await pc.IsarMessageDb.open(name: 'pc_stress_media_b');
      cryptoA = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
      cryptoB = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
      await cryptoA.generateAndStoreKeys();
      await cryptoB.generateAndStoreKeys();

      final tA = pc.InMemoryPipeTransport();
      final tB = pc.InMemoryPipeTransport();
      tA.linkPeer(tB);
      tB.linkPeer(tA);
      syncA = pc.SyncEngine(db: dbA, crypto: cryptoA, transport: tA);
      syncB = pc.SyncEngine(db: dbB, crypto: cryptoB, transport: tB);
      await syncA.start();
      await syncB.start();
      tA.open();
      tB.open();
    });

    tearDownAll(() async {
      await syncA.stop();
      await syncB.stop();
      await dbA.close();
      await dbB.close();
    });

    test('send 100 media and measure replication/throughput + verify decryption of samples', () async {
      final aDesc = await cryptoA.getDescriptor();
      final bDesc = await cryptoB.getDescriptor();
      expect(aDesc, isNotNull);
      expect(bDesc, isNotNull);
      final toEd = bDesc!.publicIdentity.ed25519;
      final toX = bDesc.publicIdentity.x25519;
      final fromEd = aDesc!.publicIdentity.ed25519;
      final fromX = aDesc.publicIdentity.x25519;

      // Canonical participants key (duplicate of TxBuilder logic)
      String participantsKey(String a, String b) => a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

      final txBuilderA = pc.TxBuilder(crypto: cryptoA, db: dbA);

      final received = <String, DateTime>{};
      final bytesSentByTx = <String, int>{};
      final startTimes = <String, DateTime>{};
      final sub = syncB.onTxReceived().listen((tx) {
        received[tx.txId] = DateTime.now().toUtc();
        final st = startTimes[tx.txId];
        if (st != null) {
          recorder.record('media_replication_ms', received[tx.txId]!.difference(st), bytes: bytesSentByTx[tx.txId] ?? 0);
        }
      });

      final rnd = Random(42);
      final total = 100;
      int totalBytes = 0;
      final beginMem = await getResidentMemoryBytes();
      final begin = DateTime.now().toUtc();

      for (var i = 0; i < total; i++) {
        // Sizes between 32KB and 160KB to produce 1-3 chunks with default chunkSize 512KB
        final size = 32 * 1024 + (rnd.nextInt(5) * 32 * 1024);
        final bytes = Uint8List.fromList(List<int>.generate(size, (j) => (j + i) % 256));
        totalBytes += size;
        final t0 = DateTime.now().toUtc();
        final tx = await txBuilderA.createMediaTx(
          toEd25519: toEd,
          toX25519: toX,
          bytes: bytes,
          mime: 'application/octet-stream',
        );
        final t1 = DateTime.now().toUtc();
        recorder.record('create_media_ms', t1.difference(t0), bytes: size);
        bytesSentByTx[tx.txId] = size;
        startTimes[tx.txId] = DateTime.now().toUtc();
        await syncA.announceTx(tx.txId);
      }

      // Await until all received or timeout
      final done = Completer<void>();
      Timer? timeout;
      void checkDone() {
        if (received.length >= total && !done.isCompleted) {
          done.complete();
        }
      }
      timeout = Timer(const Duration(seconds: 90), () {
        if (!done.isCompleted) done.complete();
      });
      final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => checkDone());
      await done.future;
      timeout?.cancel();
      ticker.cancel();
      await sub.cancel();

      // Verify B has the conversation references
      final convo = await dbB.getConversation(a: fromEd, b: toEd, limit: total + 10);
      expect(convo.length, received.length);

      // Decrypt and verify a few samples (first, middle, last)
      final sampleIdx = <int>{0, total ~/ 2, total - 1};
      int verified = 0;
      for (final idx in sampleIdx) {
        final tx = convo[idx];
        // Load manifest and reconstruct bytes
        final manifestId = tx.payload.chunkRef!;
        final manifestChunk = await dbB.getChunk(manifestId);
        expect(manifestChunk, isNotNull);
        final shared = await cryptoB.sharedSecret(pc.b64urlDecode(fromX));
        final cc = codec.ChunkCodec();
        final manJson = await cc.decrypt(
          encoded: manifestChunk!.data!,
          sharedSecret: shared,
          participantsKey: participantsKey(fromX, toX),
        );
        final manifest = jsonDecode(String.fromCharCodes(manJson)) as Map<String, dynamic>;
        final chunks = (manifest['chunks'] as List).cast<Map>();
        final out = BytesBuilder(copy: false);
        for (final c in chunks) {
          final id = c['id'] as String;
          final ce = await dbB.getChunk(id);
          expect(ce, isNotNull);
          final plain = await cc.decrypt(
            encoded: ce!.data!,
            sharedSecret: shared,
            participantsKey: participantsKey(fromX, toX),
          );
          out.add(plain);
        }
        // Original bytes were generated deterministically; validate size only here
        final size = tx.payload.sizeBytes!;
        expect(out.toBytes().length, size);
        verified++;
      }
      expect(verified, sampleIdx.length);

      final end = DateTime.now().toUtc();
      final endMem = await getResidentMemoryBytes();
      final elapsedMs = end.difference(begin).inMilliseconds;

      final report = recorder.report();
      // ignore: avoid_print
      print({
        'suite': 'stress_media_100',
        'total_sent': total,
        'total_received': received.length,
        'bytes_sent_total': totalBytes,
        'elapsed_ms': elapsedMs,
        'resident_memory_begin': beginMem,
        'resident_memory_end': endMem,
        'resident_memory_delta': (beginMem != null && endMem != null) ? (endMem - beginMem) : null,
        'report': report.toJson(),
      });

      expect(received.length, total, reason: 'Replication did not complete within timeout');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
