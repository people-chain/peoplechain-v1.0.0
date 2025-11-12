import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart' as pc;

import 'package:pocket_coach/peoplechain_core/src/utils/perf.dart';
import 'package:pocket_coach/peoplechain_core/src/utils/memory_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stress: 1,000 text messages (A -> B) with sync latency metrics', () {
    late pc.IsarMessageDb dbA;
    late pc.IsarMessageDb dbB;
    late pc.CryptoManager cryptoA;
    late pc.CryptoManager cryptoB;
    late pc.SyncEngine syncA;
    late pc.SyncEngine syncB;
    final recorder = PerfRecorder();

    setUpAll(() async {
      dbA = await pc.IsarMessageDb.open(name: 'pc_stress_text_a');
      dbB = await pc.IsarMessageDb.open(name: 'pc_stress_text_b');
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

    test('send 1000 texts and measure replication latency/throughput', () async {
      final descB = await cryptoB.getDescriptor();
      final descA = await cryptoA.getDescriptor();
      expect(descA, isNotNull);
      expect(descB, isNotNull);
      final toEd = descB!.publicIdentity.ed25519;
      final fromEd = descA!.publicIdentity.ed25519;

      final txBuilderA = pc.TxBuilder(crypto: cryptoA, db: dbA);

      final received = <String, DateTime>{};
      final startTimes = <String, DateTime>{};
      final sub = syncB.onTxReceived().listen((tx) {
        received[tx.txId] = DateTime.now().toUtc();
        final st = startTimes[tx.txId];
        if (st != null) {
          recorder.record('replication_ms', received[tx.txId]!.difference(st));
        }
      });

      final int total = 1000;
      final beginMem = await getResidentMemoryBytes();
      final begin = DateTime.now().toUtc();

      for (var i = 0; i < total; i++) {
        final t0 = DateTime.now().toUtc();
        final tx = await txBuilderA.createTextTx(toEd25519: toEd, text: 'msg #$i from A');
        final t1 = DateTime.now().toUtc();
        recorder.record('create_text_ms', t1.difference(t0));
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
      timeout = Timer(const Duration(seconds: 60), () {
        if (!done.isCompleted) done.complete();
      });
      final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => checkDone());
      await done.future;
      timeout?.cancel();
      ticker.cancel();
      await sub.cancel();

      // Verify B has the conversation fully
      final convo = await dbB.getConversation(a: fromEd, b: toEd, limit: total + 10);
      expect(convo.length, received.length);

      final end = DateTime.now().toUtc();
      final endMem = await getResidentMemoryBytes();
      final elapsedMs = end.difference(begin).inMilliseconds;

      final report = recorder.report();
      // Emit a structured log line for downstream consumption
      // ignore: avoid_print
      print({
        'suite': 'stress_text_1000',
        'total_sent': total,
        'total_received': received.length,
        'elapsed_ms': elapsedMs,
        'resident_memory_begin': beginMem,
        'resident_memory_end': endMem,
        'resident_memory_delta': (beginMem != null && endMem != null) ? (endMem - beginMem) : null,
        'report': report.toJson(),
      });

      expect(received.length, total, reason: 'Replication did not complete within timeout');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
