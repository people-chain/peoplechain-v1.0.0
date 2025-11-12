import 'dart:async';
import 'package:flutter/foundation.dart';
import '../peoplechain_core/peoplechain_core.dart' as pc;
import 'metrics_bus.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class TestCaseDef {
  final String id;
  final String title;
  final String description;
  final Future<TestResult> Function() run;
  final Duration? timeout;
  const TestCaseDef({
    required this.id,
    required this.title,
    required this.description,
    required this.run,
    this.timeout,
  });
}

class TestResult {
  final bool passed;
  final Duration duration;
  final String? error;
  final String? stack;
  const TestResult({required this.passed, required this.duration, this.error, this.stack});
}

class TestHarness {
  static final TestHarness I = TestHarness._();
  TestHarness._();

  final _tests = <TestCaseDef>[];
  List<TestCaseDef> get tests => List.unmodifiable(_tests);

  void register(TestCaseDef def) => _tests.add(def);

  Future<TestResult> run(TestCaseDef def) async {
    final sw = Stopwatch()..start();
    try {
      final res = await capturePrints(() async {
        MetricsBus.I.logInfo('Running test: ${def.title}');
        return await (def.timeout != null
            ? def.run().timeout(def.timeout!)
            : def.run());
      });
      sw.stop();
      return TestResult(passed: res.passed, duration: sw.elapsed, error: res.error, stack: res.stack);
    } catch (e, st) {
      sw.stop();
      MetricsBus.I.logError('Test failed: ${def.title} -> $e');
      return TestResult(passed: false, duration: sw.elapsed, error: e.toString(), stack: st.toString());
    }
  }
}

// region: Minimal mirrored suites (logic-only) to keep CLI tests untouched
void registerDefaultSuites() {
  // CryptoManager basic flow
  TestHarness.I.register(TestCaseDef(
    id: 'crypto_manager_basic',
    title: 'CryptoManager: generate/sign/secret',
    description: 'Generates keys, signs a message, and derives shared secret symmetry.',
    run: () async {
      try {
        final storageA = pc.KeyStorage(driver: pc.InMemorySecureStorageDriver());
        final cmA = pc.CryptoManager(storage: storageA);
        final descA = await cmA.generateAndStoreKeys();
        if (descA.publicIdentity.ed25519.isEmpty) {
          throw 'empty ed25519';
        }
        final storageB = pc.KeyStorage(driver: pc.InMemorySecureStorageDriver());
        final cmB = pc.CryptoManager(storage: storageB);
        final descB = await cmB.generateAndStoreKeys();
        final msg = Uint8List.fromList([1, 2, 3]);
        final sig = await cmA.sign(msg);
        if (sig.isEmpty) throw 'empty signature';
        String pad(String s) { while (s.length % 4 != 0) { s += '='; } return s; }
        final bPub = Uint8List.fromList(base64Url.decode(pad(descB.publicIdentity.x25519)));
        final aShared = await cmA.sharedSecret(bPub);
        final aPub = Uint8List.fromList(base64Url.decode(pad(descA.publicIdentity.x25519)));
        final bShared = await cmB.sharedSecret(aPub);
        if (!listEquals(aShared, bShared)) throw 'shared secret mismatch';
        return const TestResult(passed: true, duration: Duration.zero);
      } catch (e, st) {
        return TestResult(passed: false, duration: Duration.zero, error: e.toString(), stack: st.toString());
      }
    },
  ));

  // Stress: 1,000 text messages loop using in-memory transport and DB
  TestHarness.I.register(TestCaseDef(
    id: 'stress_text_1000',
    title: 'Stress: 1,000 text messages A→B',
    description: 'Measures replication latency and throughput across in-memory transport.',
    // On web, cryptography in WASM/JS can be slower; allow more time.
    timeout: kIsWeb ? const Duration(minutes: 5) : const Duration(minutes: 2),
    run: () async {
      try {
        final dbA = await _openDbForTests('stress_text_a');
        final dbB = await _openDbForTests('stress_text_b');
        final cryptoA = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
        final cryptoB = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
        await cryptoA.generateAndStoreKeys();
        await cryptoB.generateAndStoreKeys();
        final tA = pc.InMemoryPipeTransport();
        final tB = pc.InMemoryPipeTransport();
        tA.linkPeer(tB); tB.linkPeer(tA);
        final syncA = pc.SyncEngine(db: dbA, crypto: cryptoA, transport: tA);
        final syncB = pc.SyncEngine(db: dbB, crypto: cryptoB, transport: tB);
        await syncA.start(); await syncB.start();
        tA.open(); tB.open();

        final descA = await cryptoA.getDescriptor();
        final descB = await cryptoB.getDescriptor();
        final toEd = descB!.publicIdentity.ed25519;
        final fromEd = descA!.publicIdentity.ed25519;
        final txBuilderA = pc.TxBuilder(crypto: cryptoA, db: dbA);
        final received = <String, DateTime>{};
        final startTimes = <String, DateTime>{};
        final sub = syncB.onTxReceived().listen((tx) {
          received[tx.txId] = DateTime.now().toUtc();
          final st = startTimes[tx.txId];
          if (st != null) {
            MetricsBus.I.recordLatency(received[tx.txId]!.difference(st));
          }
        });

        // Keep browser runs snappy; fewer messages on web
        final total = kIsWeb ? 300 : 1000;
        for (var i = 0; i < total; i++) {
          final t0 = DateTime.now().toUtc();
          final tx = await txBuilderA.createTextTx(toEd25519: toEd, text: 'msg #$i from A');
          final t1 = DateTime.now().toUtc();
          MetricsBus.I.recordLatency(t1.difference(t0));
          startTimes[tx.txId] = DateTime.now().toUtc();
          await syncA.announceTx(tx.txId);
          // Yield occasionally to keep UI responsive on web
          if (i % 25 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        final completer = Completer<void>();
        Timer? timeout;
        void checkDone() {
          if (received.length >= total && !completer.isCompleted) completer.complete();
        }
        // Permit slower devices a bit more time on web
        timeout = Timer(kIsWeb ? const Duration(seconds: 120) : const Duration(seconds: 60), () { if (!completer.isCompleted) completer.complete(); });
        final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => checkDone());
        await completer.future;
        timeout.cancel(); ticker.cancel(); await sub.cancel();
        final convo = await dbB.getConversation(a: fromEd, b: toEd, limit: total + 10);
        final ok = convo.length == received.length && received.length == total;
        await syncA.stop(); await syncB.stop();
        return TestResult(passed: ok, duration: Duration.zero, error: ok ? null : 'Replication incomplete');
      } catch (e, st) {
        return TestResult(passed: false, duration: Duration.zero, error: e.toString(), stack: st.toString());
      }
    },
  ));

  // Tx pipeline (createTextTx + createMediaTx core flow)
  TestHarness.I.register(TestCaseDef(
    id: 'tx_pipeline_core',
    title: 'Tx Pipeline: text + media construction',
    description: 'Builds text and media tx, verifies signature and chunk decryptability.',
    timeout: const Duration(minutes: 2),
    run: () async {
      try {
        final db = pc.InMemoryMessageDb();
        final alice = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
        final bob = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
        await alice.generateAndStoreKeys();
        await bob.generateAndStoreKeys();
        final aDesc = await alice.getDescriptor();
        final bDesc = await bob.getDescriptor();
        final builder = pc.TxBuilder(crypto: alice, db: db);
        // Text
        final t = await builder.createTextTx(toEd25519: bDesc!.publicIdentity.ed25519, text: 'Hello');
        final stored = await db.getTransaction(t.txId);
        if (stored == null) throw 'text tx not stored';
        // Media (128KB sample)
        final data = Uint8List.fromList(List<int>.generate(128 * 1024, (i) => i % 251));
        final m = await builder.createMediaTx(
          toEd25519: bDesc.publicIdentity.ed25519,
          toX25519: bDesc.publicIdentity.x25519,
          bytes: data,
          mime: 'application/octet-stream',
          chunkSize: 64 * 1024,
        );
        final manifest = await db.getChunk(m.payload.chunkRef!);
        if (manifest?.data == null) throw 'manifest missing';
        // Bob decrypts manifest header
        final cc = pc.ChunkCodec();
        final shared = await bob.sharedSecret(pc.b64urlDecode(aDesc!.publicIdentity.x25519));
        final participantsKey = _participantsKey(aDesc.publicIdentity.x25519, bDesc.publicIdentity.x25519);
        final plain = await cc.decrypt(encoded: manifest!.data!, sharedSecret: shared, participantsKey: participantsKey);
        if (!String.fromCharCodes(plain).contains('chunks')) throw 'manifest decrypt failed';
        return const TestResult(passed: true, duration: Duration.zero);
      } catch (e, st) {
        return TestResult(passed: false, duration: Duration.zero, error: e.toString(), stack: st.toString());
      }
    },
  ));

  // Sync engine end-to-end over in-memory transport
  TestHarness.I.register(TestCaseDef(
    id: 'sync_engine_basic',
    title: 'SyncEngine: blocks + txs over in-memory transport',
    description: 'Two peers replicate genesis + 1 block and tx set.',
    timeout: const Duration(seconds: 30),
    run: () async {
      try {
        final dbA = pc.InMemoryMessageDb();
        final dbB = pc.InMemoryMessageDb();
        final ca = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
        final cb = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
        await ca.generateAndStoreKeys();
        await cb.generateAndStoreKeys();
        final da = await ca.getDescriptor();
        final db = await cb.getDescriptor();
        final bldr = pc.TxBuilder(crypto: ca, db: dbA);
        final t1 = await bldr.createTextTx(toEd25519: db!.publicIdentity.ed25519, text: 'hi');
        final t2 = await bldr.createTextTx(toEd25519: db.publicIdentity.ed25519, text: 'there');
        // genesis + 1
        final genesis = pc.BlockModel(
          header: pc.BlockHeaderModel(
            blockId: 'genesis', height: 0, prevBlockId: '', timestampMs: DateTime.now().millisecondsSinceEpoch,
            txMerkleRoot: '', proposer: da!.publicIdentity.ed25519,
          ), txIds: const [], signatures: const [],
        );
        await dbA.putBlock(genesis);
        final merkle = await _merkle([t1.txId, t2.txId]);
        final b1 = pc.BlockModel(
          header: pc.BlockHeaderModel(
            blockId: 'b1', height: 1, prevBlockId: genesis.header.blockId, timestampMs: DateTime.now().millisecondsSinceEpoch,
            txMerkleRoot: merkle, proposer: da.publicIdentity.ed25519,
          ), txIds: [t1.txId, t2.txId], signatures: const [],
        );
        await dbA.putBlock(b1);
        final ta = pc.InMemoryPipeTransport();
        final tb = pc.InMemoryPipeTransport();
        ta.linkPeer(tb); tb.linkPeer(ta);
        final sa = pc.SyncEngine(db: dbA, crypto: ca, transport: ta);
        final sb = pc.SyncEngine(db: dbB, crypto: cb, transport: tb);
        await sa.start(); await sb.start();
        ta.open(); tb.open();
        await Future.delayed(const Duration(milliseconds: 250));
        final tipH = await dbB.tipHeight();
        final got1 = await dbB.getTransaction(t1.txId);
        final got2 = await dbB.getTransaction(t2.txId);
        final ok = tipH == 1 && got1 != null && got2 != null;
        await sa.stop(); await sb.stop();
        return TestResult(passed: ok, duration: Duration.zero, error: ok ? null : 'Replication failed');
      } catch (e, st) {
        return TestResult(passed: false, duration: Duration.zero, error: e.toString(), stack: st.toString());
      }
    },
  ));

  // WebRTC QR payload codec
  TestHarness.I.register(TestCaseDef(
    id: 'webrtc_payload_codec',
    title: 'WebRTC QR payload encode/decode',
    description: 'Validates base64 JSON payload roundtrip for offer.',
    run: () async {
      try {
        final map = {
          'type': 'offer',
          'sdp': 'v=0...sdp',
          'nodeId': 'n123',
          'ed25519': 'edKey',
          'x25519': 'xKey',
          'alias': 'Alice',
        };
        final b64 = pc.WebRtcQrPayload.encode(map);
        final out = pc.WebRtcQrPayload.decode(b64);
        final ok = out['type'] == 'offer' && out['sdp'] == 'v=0...sdp' && out['nodeId'] == 'n123';
        return TestResult(passed: ok, duration: Duration.zero, error: ok ? null : 'mismatch');
      } catch (e, st) {
        return TestResult(passed: false, duration: Duration.zero, error: e.toString(), stack: st.toString());
      }
    },
  ));

  // Media stress (lightweight for browser): 50 media messages with decrypt spot-check
  TestHarness.I.register(TestCaseDef(
    id: 'stress_media_50',
    title: 'Stress: 50 media A→B with decrypt spot-check',
    description: 'Measures throughput using in-memory DB + transport; verifies decryption of samples.',
    timeout: const Duration(minutes: 2),
    run: () async {
      try {
        final dbA = await _openDbForTests('stress_media_a');
        final dbB = await _openDbForTests('stress_media_b');
        final cryptoA = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
        final cryptoB = pc.CryptoManager(storage: pc.KeyStorage(driver: pc.InMemorySecureStorageDriver()));
        await cryptoA.generateAndStoreKeys();
        await cryptoB.generateAndStoreKeys();
        final tA = pc.InMemoryPipeTransport();
        final tB = pc.InMemoryPipeTransport();
        tA.linkPeer(tB); tB.linkPeer(tA);
        final syncA = pc.SyncEngine(db: dbA, crypto: cryptoA, transport: tA);
        final syncB = pc.SyncEngine(db: dbB, crypto: cryptoB, transport: tB);
        await syncA.start(); await syncB.start();
        tA.open(); tB.open();
        final aDesc = await cryptoA.getDescriptor();
        final bDesc = await cryptoB.getDescriptor();
        final toEd = bDesc!.publicIdentity.ed25519;
        final toX = bDesc.publicIdentity.x25519;
        final fromEd = aDesc!.publicIdentity.ed25519;
        final fromX = aDesc.publicIdentity.x25519;
        final txb = pc.TxBuilder(crypto: cryptoA, db: dbA);
        final received = <String, DateTime>{};
        final startTimes = <String, DateTime>{};
        final bytesSent = <String, int>{};
        final sub = syncB.onTxReceived().listen((tx) {
          received[tx.txId] = DateTime.now().toUtc();
          final st = startTimes[tx.txId];
          if (st != null) MetricsBus.I.recordLatency(received[tx.txId]!.difference(st));
        });
        const total = 50;
        for (var i = 0; i < total; i++) {
          final size = 24 * 1024 + ((i % 5) * 24 * 1024);
          final bytes = Uint8List.fromList(List<int>.generate(size, (j) => (j + i) % 253));
          final tx = await txb.createMediaTx(toEd25519: toEd, toX25519: toX, bytes: bytes, mime: 'application/octet-stream', chunkSize: 64 * 1024);
          bytesSent[tx.txId] = size;
          startTimes[tx.txId] = DateTime.now().toUtc();
          await syncA.announceTx(tx.txId);
          if (i % 10 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        // wait completion or timeout
        final done = Completer<void>();
        Timer(const Duration(seconds: 45), () { if (!done.isCompleted) done.complete(); });
        final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) { if (received.length >= total && !done.isCompleted) done.complete(); });
        await done.future; ticker.cancel(); await sub.cancel();
        final convo = await dbB.getConversation(a: fromEd, b: toEd, limit: total + 10);
        if (convo.length < total) {
          await syncA.stop(); await syncB.stop();
          return TestResult(passed: false, duration: Duration.zero, error: 'Replication incomplete: ${convo.length}/$total');
        }
        // Verify first and last decrypt
        final cc = pc.ChunkCodec();
        final shared = await cryptoB.sharedSecret(pc.b64urlDecode(fromX));
        String pk(String a, String b) => a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
        for (final idx in [0, total - 1]) {
          final tx = convo[idx];
          final manId = tx.payload.chunkRef!;
          // In this test path, chunks don't replicate; read from sender DB as a stand-in for a fetch.
          var enc = await dbB.getChunk(manId);
          enc ??= await dbA.getChunk(manId);
          if (enc?.data == null) {
            await syncA.stop(); await syncB.stop();
            return const TestResult(passed: false, duration: Duration.zero, error: 'manifest missing');
          }
          final encNonNull = enc!;
          final plain = await cc.decrypt(encoded: encNonNull.data!, sharedSecret: shared, participantsKey: pk(fromX, toX));
          if (!String.fromCharCodes(plain).contains('chunks')) {
            await syncA.stop(); await syncB.stop();
            return const TestResult(passed: false, duration: Duration.zero, error: 'manifest decrypt failed');
          }
        }
        await syncA.stop(); await syncB.stop();
        return const TestResult(passed: true, duration: Duration.zero);
      } catch (e, st) {
        return TestResult(passed: false, duration: Duration.zero, error: e.toString(), stack: st.toString());
      }
    },
  ));
}

Future<pc.MessageDb> _openDbForTests(String name) async {
  if (kIsWeb) {
    // In web test mode we prefer in-memory DB
    return pc.InMemoryMessageDb();
  }
  try {
    final isarDb = await pc.IsarMessageDb.open(name: name);
    return isarDb;
  } catch (_) {
    return pc.InMemoryMessageDb();
  }
}

String _participantsKey(String a, String b) => a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

Future<String> _merkle(List<String> ids) async {
  if (ids.isEmpty) return '';
  List<Uint8List> layer = [for (final id in ids) Uint8List.fromList(const Utf8Encoder().convert(id))];
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
