import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto_manager.dart';
import '../db/message_db.dart';
import '../models/chain_models.dart';
import '../models/keypair.dart';
import 'chunk_codec.dart';

class TxBuilder {
  final CryptoManager crypto;
  final MessageDb db;

  TxBuilder({required this.crypto, required this.db});

  // region: Text transaction
  Future<TxModel> createTextTx({
    required String toEd25519,
    required String text,
    int? timestampMs,
  }) async {
    final desc = await crypto.getDescriptor();
    if (desc == null) {
      throw StateError('No key descriptor available');
    }
    final fromEd = desc.publicIdentity.ed25519;
    final ts = timestampMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final nonce = _randomNonce();
    final payload = TxPayloadModel(type: 'text', text: text);
    final bodyBytes = _canonicalBodyBytes(
      from: fromEd,
      to: toEd25519,
      nonce: nonce,
      timestampMs: ts,
      payload: payload,
    );
    final sig = await crypto.sign(bodyBytes);
    final txId = await _txIdFrom(bodyBytes, sig);
    final tx = TxModel(
      txId: txId,
      from: fromEd,
      to: toEd25519,
      nonce: nonce,
      timestampMs: ts,
      payload: payload,
      signature: b64url(sig),
    );
    await db.putTransaction(tx);
    return tx;
  }
  // endregion

  // region: Encrypted text transaction (stores ciphertext as a single chunk)
  Future<TxModel> createEncryptedTextTx({
    required String toEd25519,
    required String toX25519,
    required String text,
    int? timestampMs,
  }) async {
    final desc = await crypto.getDescriptor();
    if (desc == null) {
      throw StateError('No key descriptor available');
    }
    // Derive shared secret
    final shared = await crypto.sharedSecret(b64urlDecode(toX25519));
    final codec = ChunkCodec();
    final participantsKey = TxBuilder.participantsKey(desc.publicIdentity.x25519, toX25519);

    final clear = Uint8List.fromList(utf8.encode(text));
    final enc = await codec.encrypt(plaintext: clear, sharedSecret: shared, participantsKey: participantsKey);
    final cid = await chunkIdFromPlaintext(clear);
    final chunk = ChunkModel(
      chunkId: cid,
      type: 'text',
      sizeBytes: clear.length,
      hash: await _sha256B64(clear),
      data: enc,
      mime: 'text/plain',
    );
    await db.putChunk(chunk);

    // Build the TX referencing the encrypted text chunk
    final ts = timestampMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final nonce = _randomNonce();
    final payload = TxPayloadModel(type: 'text', chunkRef: cid, mime: 'text/plain', sizeBytes: clear.length);
    final bodyBytes = _canonicalBodyBytes(
      from: desc.publicIdentity.ed25519,
      to: toEd25519,
      nonce: nonce,
      timestampMs: ts,
      payload: payload,
    );
    final sig = await crypto.sign(bodyBytes);
    final txId = await _txIdFrom(bodyBytes, sig);
    final tx = TxModel(
      txId: txId,
      from: desc.publicIdentity.ed25519,
      to: toEd25519,
      nonce: nonce,
      timestampMs: ts,
      payload: payload,
      signature: b64url(sig),
    );
    await db.putTransaction(tx);
    return tx;
  }
  // endregion

  // region: Media/File transaction with chunking + encryption
  Future<TxModel> createMediaTx({
    required String toEd25519,
    required String toX25519,
    required Uint8List bytes,
    required String mime,
    int chunkSize = 512 * 1024,
    int? timestampMs,
  }) async {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    final desc = await crypto.getDescriptor();
    if (desc == null) throw StateError('No key descriptor available');
    final from = desc.publicIdentity;
    final participantsKey = TxBuilder.participantsKey(from.x25519, toX25519);
    // Shared secret using x25519
    final shared = await crypto.sharedSecret(b64urlDecode(toX25519));
    final codec = ChunkCodec();

    final total = bytes.length;
    final chunks = <Map<String, dynamic>>[];
    int offset = 0;
    int index = 0;
    while (offset < total) {
      final end = (offset + chunkSize) > total ? total : (offset + chunkSize);
      final slice = bytes.sublist(offset, end);
      // Compression: none (placeholder for future zstd)
      final plaintext = slice; // no compression in M3
      final enc = await codec.encrypt(
        plaintext: plaintext,
        sharedSecret: shared,
        participantsKey: participantsKey,
      );
      final cid = await chunkIdFromPlaintext(plaintext);
      final model = ChunkModel(
        chunkId: cid,
        type: 'media',
        sizeBytes: plaintext.length,
        hash: await _sha256B64(plaintext),
        data: enc,
        mime: mime,
      );
      await db.putChunk(model);
      chunks.add({'id': cid, 'idx': index, 'size': plaintext.length});
      index += 1;
      offset = end;
    }

    // Build manifest JSON, encrypt and store as a chunk
    final manifest = jsonEncode({
      'version': 1,
      'total_size': total,
      'mime': mime,
      'chunks': chunks,
    });
    final manifestBytes = Uint8List.fromList(utf8.encode(manifest));
    final manifestEnc = await codec.encrypt(
      plaintext: manifestBytes,
      sharedSecret: shared,
      participantsKey: participantsKey,
    );
    final manifestId = await chunkIdFromPlaintext(manifestBytes);
    final manifestModel = ChunkModel(
      chunkId: manifestId,
      type: 'file',
      sizeBytes: manifestBytes.length,
      hash: await _sha256B64(manifestBytes),
      data: manifestEnc,
      mime: 'application/vnd.peoplechain.file-manifest+json',
    );
    await db.putChunk(manifestModel);

    // Create TX referencing manifest
    final ts = timestampMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final nonce = _randomNonce();
    final payload = TxPayloadModel(
      type: 'media',
      chunkRef: manifestId,
      mime: mime,
      sizeBytes: total,
    );
    final bodyBytes = _canonicalBodyBytes(
      from: from.ed25519,
      to: toEd25519,
      nonce: nonce,
      timestampMs: ts,
      payload: payload,
    );
    final sig = await crypto.sign(bodyBytes);
    final txId = await _txIdFrom(bodyBytes, sig);
    final tx = TxModel(
      txId: txId,
      from: from.ed25519,
      to: toEd25519,
      nonce: nonce,
      timestampMs: ts,
      payload: payload,
      signature: b64url(sig),
    );
    await db.putTransaction(tx);
    return tx;
  }
  // endregion

  // region: Helpers
  static String participantsKey(String a, String b) {
    // Canonical order
    return a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
  }

  // In later milestones, mapping ed25519<->x25519 comes from NodeRecord exchange.

  static int _randomNonce() => Random.secure().nextInt(0x7fffffff);

  static Uint8List _canonicalBodyBytes({
    required String from,
    required String to,
    required int nonce,
    required int timestampMs,
    required TxPayloadModel payload,
  }) {
    // Canonical JSON without whitespace, deterministic field order
    final map = <String, dynamic>{
      'from': from,
      'to': to,
      'nonce': nonce,
      'timestamp_ms': timestampMs,
      'payload': payload.toJson(),
    };
    final s = jsonEncode(map);
    return Uint8List.fromList(utf8.encode(s));
  }

  static Future<String> _txIdFrom(Uint8List body, Uint8List sig) async {
    final d = await Sha256().hash(<int>[...body, ...sig]);
    return b64url(Uint8List.fromList(d.bytes));
  }

  static Future<String> _sha256B64(Uint8List data) async {
    final d = await Sha256().hash(data);
    return b64url(Uint8List.fromList(d.bytes));
  }
  // endregion
}
