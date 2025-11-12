import 'dart:async';
import 'dart:typed_data';

import 'package:isar/isar.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import '../models/chain_models.dart';
import 'message_db.dart';
import 'isar_models.dart';
import 'isar_factory.dart';

/// Isar-backed implementation of MessageDb.
///
/// Generated collection schemas are checked into source (see isar_models.g.dart)
/// so we do not rely on build_runner at runtime.
class IsarMessageDb implements MessageDb {
  final Isar? _isar;
  final MessageDb? _fallback;

  IsarMessageDb._(this._isar) : _fallback = null;
  IsarMessageDb._fallback(this._fallback) : _isar = null;

  static Future<IsarMessageDb> open({String? directoryPath, String name = 'peoplechain'}) async {
    // On web test mode we fallback to in-memory DB to avoid Isar 3.x web limitation.
    // The Testing Dashboard toggles this mode.
    try {
      if (kIsWeb) {
        // Try in-memory directly on web; IndexedDB via Isar 3.x is not supported.
        return IsarMessageDb._fallback(InMemoryMessageDb());
      }
      // Protect against potential native open hangs by adding a timeout.
      // If the timeout triggers, we log and fall back to in-memory so the app can start.
      final isar = await IsarFactory
          .open(directoryPath: directoryPath, name: name)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('[IsarMessageDb] Isar open timed out after 10s, falling back to in-memory DB');
        throw TimeoutException('Isar open timed out');
      });
      return IsarMessageDb._(isar);
    } catch (_) {
      // Friendly fallback on any failure
      debugPrint('[IsarMessageDb] Isar open failed, using in-memory DB fallback');
      return IsarMessageDb._fallback(InMemoryMessageDb());
    }
  }

  Future<void> close() async {
    if (_isar != null) {
      await _isar!.close();
    }
  }

  // region: Chunks
  @override
  Future<void> putChunk(ChunkModel chunk) async {
    if (_fallback != null) return _fallback!.putChunk(chunk);
    final entity = ChunkEntity()
      ..chunkId = chunk.chunkId
      ..type = chunk.type
      ..sizeBytes = chunk.sizeBytes
      ..hash = chunk.hash
      ..data = chunk.data
      ..mime = chunk.mime;
    final isar = _isar!;
    await isar.writeTxn(() async {
      await isar.collection<ChunkEntity>().putByIndex('chunkId', entity);
    });
  }

  @override
  Future<ChunkModel?> getChunk(String chunkId) async {
    if (_fallback != null) return _fallback!.getChunk(chunkId);
    final isar = _isar!;
    final entity = await isar.collection<ChunkEntity>().getByIndex('chunkId', [chunkId]);
    if (entity == null) return null;
    return ChunkModel(
      chunkId: entity.chunkId,
      type: entity.type,
      sizeBytes: entity.sizeBytes,
      hash: entity.hash,
      data: entity.data != null ? Uint8List.fromList(entity.data!) : null,
      mime: entity.mime,
    );
  }
  // endregion

  // region: Transactions
  static String _participantsKey(String a, String b) {
    if (a.compareTo(b) <= 0) return '$a|$b';
    return '$b|$a';
  }

  @override
  Future<void> putTransaction(TxModel tx) async {
    if (_fallback != null) return _fallback!.putTransaction(tx);
    final entity = TxEntity()
      ..txId = tx.txId
      ..from = tx.from
      ..to = tx.to
      ..nonce = tx.nonce
      ..timestampMs = tx.timestampMs
      ..participantsKey = _participantsKey(tx.from, tx.to)
      ..payloadType = tx.payload.type
      ..payloadText = tx.payload.text
      ..payloadChunkRef = tx.payload.chunkRef
      ..payloadMime = tx.payload.mime
      ..payloadSizeBytes = tx.payload.sizeBytes ?? 0
      ..signature = tx.signature;

    final convKey = entity.participantsKey;
    final ref = _refFor(tx.timestampMs, tx.txId);
    final isar = _isar!;
    await isar.writeTxn(() async {
      await isar.collection<TxEntity>().putByIndex('txId', entity);
      final convCol = isar.collection<ConversationEntity>();
      var bucket = await convCol.getByIndex('key', [convKey]);
      bucket ??= ConversationEntity()..key = convKey..txRefs = const [];
      final list = bucket.txRefs.toList();
      final idx = _lowerBound(list, ref);
      if (idx >= list.length || list[idx] != ref) {
        list.insert(idx, ref);
      }
      bucket.txRefs = list;
      await convCol.putByIndex('key', bucket);
    });
  }

  @override
  Future<TxModel?> getTransaction(String txId) async {
    if (_fallback != null) return _fallback!.getTransaction(txId);
    final isar = _isar!;
    final e = await isar.collection<TxEntity>().getByIndex('txId', [txId]);
    if (e == null) return null;
    return TxModel(
      txId: e.txId,
      from: e.from,
      to: e.to,
      nonce: e.nonce,
      timestampMs: e.timestampMs,
      payload: TxPayloadModel(
        type: e.payloadType,
        text: e.payloadText,
        chunkRef: e.payloadChunkRef,
        mime: e.payloadMime,
        sizeBytes: e.payloadSizeBytes == 0 ? null : e.payloadSizeBytes,
      ),
      signature: e.signature,
    );
  }

  @override
  Future<List<TxModel>> getConversation({required String a, required String b, int? limit}) async {
    if (_fallback != null) return _fallback!.getConversation(a: a, b: b, limit: limit);
    final key = _participantsKey(a, b);
    final isar = _isar!;
    final bucket = await isar.collection<ConversationEntity>().getByIndex('key', [key]);
    if (bucket == null || bucket.txRefs.isEmpty) return <TxModel>[];
    final refs = limit != null && bucket.txRefs.length > limit
        ? bucket.txRefs.sublist(bucket.txRefs.length - limit)
        : bucket.txRefs;
    final txCol = isar.collection<TxEntity>();
    final result = <TxModel>[];
    for (final ref in refs) {
      final id = _txIdFromRef(ref);
      final e = await txCol.getByIndex('txId', [id]);
      if (e == null) continue;
      result.add(TxModel(
        txId: e.txId,
        from: e.from,
        to: e.to,
        nonce: e.nonce,
        timestampMs: e.timestampMs,
        payload: TxPayloadModel(
          type: e.payloadType,
          text: e.payloadText,
          chunkRef: e.payloadChunkRef,
          mime: e.payloadMime,
          sizeBytes: e.payloadSizeBytes == 0 ? null : e.payloadSizeBytes,
        ),
        signature: e.signature,
      ));
    }
    return result;
  }
  // endregion

  // region: Blocks
  @override
  Future<void> putBlock(BlockModel block) async {
    if (_fallback != null) return _fallback!.putBlock(block);
    final e = BlockEntity()
      ..blockId = block.header.blockId
      ..height = block.header.height
      ..prevBlockId = block.header.prevBlockId
      ..timestampMs = block.header.timestampMs
      ..txMerkleRoot = block.header.txMerkleRoot
      ..proposer = block.header.proposer
      ..txIds = block.txIds
      ..signatures = block.signatures.map((s) => '${s.signer}|${s.signature}').toList();
    final isar = _isar!;
    await isar.writeTxn(() async {
      await isar.collection<BlockEntity>().putByIndex('blockId', e);
      // Also ensure height uniqueness by using height index replacement
      await isar.collection<BlockEntity>().putByIndex('height', e);
    });
  }

  @override
  Future<BlockModel?> getBlockById(String blockId) async {
    if (_fallback != null) return _fallback!.getBlockById(blockId);
    final isar = _isar!;
    final e = await isar.collection<BlockEntity>().getByIndex('blockId', [blockId]);
    if (e == null) return null;
    return _toBlockModel(e);
  }

  @override
  Future<BlockModel?> getBlockByHeight(int height) async {
    if (_fallback != null) return _fallback!.getBlockByHeight(height);
    final isar = _isar!;
    final e = await isar.collection<BlockEntity>().getByIndex('height', [height]);
    if (e == null) return null;
    return _toBlockModel(e);
  }

  @override
  Future<int> tipHeight() async {
    if (_fallback != null) return _fallback!.tipHeight();
    final isar = _isar!;
    int h = 0;
    while (true) {
      final e = await isar.collection<BlockEntity>().getByIndex('height', [h]);
      if (e == null) break;
      h++;
    }
    if (h == 0) return -1;
    return h - 1;
  }

  BlockModel _toBlockModel(BlockEntity e) {
    return BlockModel(
      header: BlockHeaderModel(
        blockId: e.blockId,
        height: e.height,
        prevBlockId: e.prevBlockId,
        timestampMs: e.timestampMs,
        txMerkleRoot: e.txMerkleRoot,
        proposer: e.proposer,
      ),
      txIds: e.txIds,
      signatures: e.signatures
          .map((s) {
            final i = s.indexOf('|');
            if (i <= 0) return const BlockSignatureModel(signer: '', signature: '');
            return BlockSignatureModel(signer: s.substring(0, i), signature: s.substring(i + 1));
          })
          .where((s) => s.signer.isNotEmpty)
          .toList(),
    );
  }
  // endregion
  // Helpers for conversation refs
  static String _refFor(int ts, String txId) {
    final s = ts.toString().padLeft(16, '0');
    return '$s:$txId';
  }

  static String _txIdFromRef(String ref) {
    final i = ref.indexOf(':');
    if (i < 0) return ref;
    return ref.substring(i + 1);
  }

  static int _lowerBound(List<String> list, String value) {
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (list[mid].compareTo(value) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
