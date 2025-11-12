import 'dart:collection';

import '../models/chain_models.dart';

/// Abstraction for the message database.
/// M2 foundation: An in-memory reference implementation to keep web/device tests green.
/// A production Isar-backed implementation will slot behind this interface.
abstract class MessageDb {
  Future<void> putChunk(ChunkModel chunk);
  Future<ChunkModel?> getChunk(String chunkId);

  Future<void> putTransaction(TxModel tx);
  Future<TxModel?> getTransaction(String txId);
  Future<List<TxModel>> getConversation({required String a, required String b, int? limit});

  Future<void> putBlock(BlockModel block);
  Future<BlockModel?> getBlockById(String blockId);
  Future<BlockModel?> getBlockByHeight(int height);
  Future<int> tipHeight();
}

class InMemoryMessageDb implements MessageDb {
  final Map<String, ChunkModel> _chunks = {};
  final Map<String, TxModel> _txs = {};
  final Map<String, BlockModel> _blocksById = {};
  final SplayTreeMap<int, String> _heightToId = SplayTreeMap();

  @override
  Future<ChunkModel?> getChunk(String chunkId) async => _chunks[chunkId];

  @override
  Future<void> putChunk(ChunkModel chunk) async {
    _chunks[chunk.chunkId] = chunk;
  }

  @override
  Future<TxModel?> getTransaction(String txId) async => _txs[txId];

  @override
  Future<void> putTransaction(TxModel tx) async {
    _txs[tx.txId] = tx;
  }

  @override
  Future<List<TxModel>> getConversation({required String a, required String b, int? limit}) async {
    final res = _txs.values.where((t) =>
        (t.from == a && t.to == b) || (t.from == b && t.to == a)).toList()
      ..sort((x, y) => x.timestampMs.compareTo(y.timestampMs));
    if (limit != null && res.length > limit) {
      return res.sublist(res.length - limit);
    }
    return res;
  }

  @override
  Future<void> putBlock(BlockModel block) async {
    _blocksById[block.header.blockId] = block;
    _heightToId[block.header.height] = block.header.blockId;
  }

  @override
  Future<BlockModel?> getBlockByHeight(int height) async {
    final id = _heightToId[height];
    if (id == null) return null;
    return _blocksById[id];
  }

  @override
  Future<BlockModel?> getBlockById(String blockId) async => _blocksById[blockId];

  @override
  Future<int> tipHeight() async => _heightToId.isEmpty ? -1 : _heightToId.lastKey() ?? -1;
}
