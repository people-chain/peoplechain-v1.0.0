import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto_manager.dart';
import '../db/message_db.dart';
import '../models/chain_models.dart';
import '../models/keypair.dart';
import '../p2p/adapters/webrtc_adapter.dart';
import 'protocol.dart';

/// SyncEngine implements bootstrap and delta synchronization over a SyncTransport.
/// - Handshake (hello/hello_ack) exchanges tip info
/// - Delta sync via get_blocks/blocks and get_txs/txs messages
/// - Conflict handling: prefer higher height; for equal height, lexicographically higher blockId
/// - Basic validation: chain linkage and tx merkle root
abstract class ConsensusHook {
  Future<bool> validate(BlockModel block);
}

class SyncEngine {
  final MessageDb db;
  final CryptoManager crypto;
  final SyncTransport transport;
  final ConsensusHook? consensus;

  final _seenMsgIds = <String>{};
  StreamSubscription? _msgSub;
  StreamSubscription? _openSub;
  final _blockAddedCtrl = StreamController<BlockModel>.broadcast();
  final _txReceivedCtrl = StreamController<TxModel>.broadcast();

  SyncEngine({required this.db, required this.crypto, required this.transport, this.consensus});

  Future<void> start() async {
    _msgSub = transport.messages().listen(_onMessage, onError: (_) {});
    _openSub = transport.onOpen().listen((_) => _sendHello());
    if (transport.isOpen) {
      // If already open, kick handshake immediately
      await _sendHello();
    }
  }

  Future<void> stop() async {
    await _msgSub?.cancel();
    await _openSub?.cancel();
    await _blockAddedCtrl.close();
    await _txReceivedCtrl.close();
  }

  // region: Public helpers for upper layers
  Future<void> announceTx(String txId) async {
    await transport.send(SyncMessage(type: 'inv_txs', payload: {'ids': [txId]}, msgId: _newMsgId()));
  }

  Future<void> announceBlock(String blockId, int height) async {
    await transport.send(SyncMessage(type: 'inv_blocks', payload: {
      'items': [
        {'id': blockId, 'height': height}
      ]
    }, msgId: _newMsgId()));
  }
  // endregion

  // region: Handshake
  Future<void> _sendHello() async {
    final tipH = await db.tipHeight();
    final tip = tipH >= 0 ? await db.getBlockByHeight(tipH) : null;
    final desc = await crypto.getDescriptor();
    await transport.send(SyncMessage(type: 'hello', payload: {
      'height': tipH,
      'tip_id': tip?.header.blockId,
      'ed25519': desc?.publicIdentity.ed25519,
      'x25519': desc?.publicIdentity.x25519,
      'ts': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, msgId: _newMsgId()));
  }

  Future<void> _onHello(Map<String, dynamic> p) async {
    // Respond with hello_ack and trigger delta sync if peer is ahead
    final localH = await db.tipHeight();
    final remoteH = (p['height'] as num).toInt();
    final remoteTip = p['tip_id'] as String?;
    await transport.send(SyncMessage(type: 'hello_ack', payload: {
      'height': localH,
      'tip_id': localH >= 0 ? (await db.getBlockByHeight(localH))?.header.blockId : null,
    }, msgId: _newMsgId()));

    if (remoteH > localH) {
      await _requestBlocks(localH + 1, remoteH);
    } else if (remoteH == localH && remoteTip != null) {
      final localTip = localH >= 0 ? await db.getBlockByHeight(localH) : null;
      if (localTip != null && localTip.header.blockId != remoteTip) {
        // Competing tips at same height: request that single block to compare
        await _requestBlocks(remoteH, remoteH);
      }
    }
  }
  // endregion

  // region: Delta sync
  Future<void> _requestBlocks(int from, int to) async {
    if (to < from) return;
    await transport.send(SyncMessage(type: 'get_blocks', payload: {
      'from': from,
      'to': to,
    }, msgId: _newMsgId()));
  }

  Future<void> _requestTxs(List<String> ids) async {
    if (ids.isEmpty) return;
    await transport.send(SyncMessage(type: 'get_txs', payload: {'ids': ids}, msgId: _newMsgId()));
  }

  Future<void> _handleBlocks(List<dynamic> blocksJson) async {
    for (final b in blocksJson) {
      final block = BlockModel.fromJson((b as Map).cast<String, dynamic>());
      // Optional consensus validation hook
      if (consensus != null) {
        final ok = await consensus!.validate(block);
        if (!ok) continue;
      }
      // Validate linkage
      if (block.header.height == 0) {
        // Genesis accepted as-is
        await _ingestBlock(block);
        continue;
      }
      final prev = await db.getBlockByHeight(block.header.height - 1);
      if (prev == null || prev.header.blockId != block.header.prevBlockId) {
        // Missing previous, request range
        final needFrom = max(0, block.header.height - 10); // conservative backfill window
        await _requestBlocks(needFrom, block.header.height);
        // skip for now; will re-process when previous arrives
        continue;
      }
      // Validate merkle root equals computed
      final merkle = await _computeTxMerkleRoot(block.txIds);
      if (merkle != block.header.txMerkleRoot) {
        // Reject invalid block
        continue;
      }
      // Ensure we have all transactions; request any missing
      final missing = <String>[];
      for (final id in block.txIds) {
        final tx = await db.getTransaction(id);
        if (tx == null) missing.add(id);
      }
      if (missing.isNotEmpty) {
        await _requestTxs(missing);
        // Defer block until txs arrive; re-request this block later
        await _requestBlocks(block.header.height, block.header.height);
        continue;
      }
      await _ingestBlock(block);
    }
  }

  Future<void> _ingestBlock(BlockModel block) async {
    final existing = await db.getBlockByHeight(block.header.height);
    if (existing == null) {
      await db.putBlock(block);
      _blockAddedCtrl.add(block);
      return;
    }
    if (existing.header.blockId == block.header.blockId) {
      // already have it
      return;
    }
    // Conflict: replace if remote preferred
    final preferRemote = _prefer(block.header.blockId, existing.header.blockId);
    if (preferRemote) {
      await db.putBlock(block);
      _blockAddedCtrl.add(block);
    }
  }

  bool _prefer(String a, String b) {
    // Deterministic tie-breaker: lexicographically larger blockId wins
    return a.compareTo(b) > 0;
  }

  Future<String> _computeTxMerkleRoot(List<String> ids) async {
    if (ids.isEmpty) return '';
    List<Uint8List> layer = [for (final id in ids) Uint8List.fromList(utf8.encode(id))];
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
  // endregion

  // region: Message handling
  Future<void> _onMessage(SyncMessage msg) async {
    if (msg.msgId != null) {
      if (_seenMsgIds.contains(msg.msgId)) return;
      _seenMsgIds.add(msg.msgId!);
    }
    final p = msg.payload;
    switch (msg.type) {
      case 'hello':
        await _onHello(p);
        break;
      case 'hello_ack':
        // Optionally trigger our own delta if peer is behind/ahead; handled on hello
        break;
      case 'get_blocks':
        await _serveBlocks((p['from'] as num).toInt(), (p['to'] as num).toInt());
        break;
      case 'blocks':
        await _handleBlocks(p['items'] as List);
        break;
      case 'get_txs':
        await _serveTxs(((p['ids'] as List).map((e) => e as String)).toList());
        break;
      case 'txs':
        await _handleTxs(p['items'] as List);
        break;
      case 'get_chunks':
        // Peer requests one or more chunks by id
        final ids = ((p['ids'] as List).map((e) => e as String)).toList(growable: false);
        await _serveChunks(ids);
        break;
      case 'chunks':
        // Incoming chunk payloads
        await _handleChunks(p['items'] as List);
        break;
      case 'inv_txs':
        await _handleInvTxs(((p['ids'] as List).map((e) => e as String)).toList());
        break;
      case 'inv_blocks':
        final items = (p['items'] as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(growable: false);
        await _handleInvBlocks(items);
        break;
      default:
        // ignore unknown
        break;
    }
  }

  Future<void> _serveBlocks(int from, int to) async {
    final items = <Map<String, dynamic>>[];
    for (var h = from; h <= to; h++) {
      final b = await db.getBlockByHeight(h);
      if (b != null) items.add(b.toJson());
    }
    if (items.isEmpty) return;
    await transport.send(SyncMessage(type: 'blocks', payload: {'items': items}, msgId: _newMsgId()));
  }

  Future<void> _serveTxs(List<String> ids) async {
    final items = <Map<String, dynamic>>[];
    for (final id in ids) {
      final tx = await db.getTransaction(id);
      if (tx != null) items.add(tx.toJson());
    }
    if (items.isEmpty) return;
    await transport.send(SyncMessage(type: 'txs', payload: {'items': items}, msgId: _newMsgId()));
  }

  Future<void> _handleTxs(List<dynamic> list) async {
    for (final m in list) {
      final tx = TxModel.fromJson((m as Map).cast<String, dynamic>());
      final existing = await db.getTransaction(tx.txId);
      if (existing == null) {
        await db.putTransaction(tx);
        _txReceivedCtrl.add(tx);
      }
      // Opportunistically fetch referenced chunk if missing
      final ref = tx.payload.chunkRef;
      if (ref != null) {
        final has = await db.getChunk(ref);
        if (has == null) {
          await _requestChunks([ref]);
        }
      }
    }
  }

  Future<void> _handleInvTxs(List<String> ids) async {
    final missing = <String>[];
    for (final id in ids) {
      final tx = await db.getTransaction(id);
      if (tx == null) missing.add(id);
    }
    if (missing.isNotEmpty) {
      await _requestTxs(missing);
    }
  }

  Future<void> _handleInvBlocks(List<Map<String, dynamic>> items) async {
    // Request any missing blocks by height
    int minH = 1 << 30;
    int maxH = -1;
    for (final it in items) {
      final h = (it['height'] as num).toInt();
      final id = it['id'] as String;
      final local = await db.getBlockByHeight(h);
      if (local == null || local.header.blockId != id) {
        if (h < minH) minH = h;
        if (h > maxH) maxH = h;
      }
    }
    if (maxH >= 0) {
      await _requestBlocks(minH, maxH);
    }
  }
  // endregion

  // region: Chunk replication
  Future<void> _requestChunks(List<String> ids) async {
    if (ids.isEmpty) return;
    await transport.send(SyncMessage(type: 'get_chunks', payload: {'ids': ids}, msgId: _newMsgId()));
  }

  Future<void> _serveChunks(List<String> ids) async {
    final items = <Map<String, dynamic>>[];
    for (final id in ids) {
      final c = await db.getChunk(id);
      if (c == null || c.data == null) continue;
      items.add({
        'id': c.chunkId,
        'type': c.type,
        'size': c.sizeBytes,
        'hash': c.hash,
        'data': b64url(c.data!),
        if (c.mime != null) 'mime': c.mime,
      });
    }
    if (items.isEmpty) return;
    await transport.send(SyncMessage(type: 'chunks', payload: {'items': items}, msgId: _newMsgId()));
  }

  Future<void> _handleChunks(List<dynamic> raw) async {
    for (final it in raw) {
      final m = (it as Map).cast<String, dynamic>();
      // Decode base64url data
      final dataB64 = m['data'] as String?;
      if (dataB64 == null) continue;
      final bytes = b64urlDecode(dataB64);
      final chunk = ChunkModel(
        chunkId: m['id'] as String,
        type: m['type'] as String,
        sizeBytes: (m['size'] as num).toInt(),
        hash: m['hash'] as String,
        data: bytes,
        mime: m['mime'] as String?,
      );
      await db.putChunk(chunk);
    }
  }
  // endregion

  String _newMsgId() => _randBase64(12);

  // region: Public event streams
  Stream<BlockModel> onBlockAdded() => _blockAddedCtrl.stream;
  Stream<TxModel> onTxReceived() => _txReceivedCtrl.stream;
  // endregion

  static String _randBase64(int len) {
    final r = Random.secure();
    final bytes = List<int>.generate(len, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// WebRTC transport adapter implementing SyncTransport.
class WebRtcSyncTransport implements SyncTransport {
  final WebRtcAdapter adapter;
  WebRtcSyncTransport(this.adapter);

  @override
  bool get isOpen => adapter.isOpen;

  @override
  Stream<SyncMessage> messages() => adapter.onJsonMessage().map((m) => SyncMessage.fromJson(m));

  @override
  Stream<void> onOpen() => adapter.onOpen();

  @override
  Future<void> send(SyncMessage message) async {
    await adapter.sendJson(message.toJson());
  }
}
