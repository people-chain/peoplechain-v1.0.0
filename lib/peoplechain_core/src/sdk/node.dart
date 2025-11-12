import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import '../crypto_manager.dart';
import '../db/isar_message_db.dart';
import '../db/message_db.dart';
import '../models/chain_models.dart';
import '../models/keypair.dart';
import '../p2p/p2p_manager.dart';
import '../p2p/peer_store.dart';
import '../p2p/adapters/webrtc_adapter.dart';
import '../sync/protocol.dart';
import '../p2p/adapters/webrtc_autodiscovery.dart';
import '../p2p/adapters/webrtc_autodiscovery_interface.dart';
import '../sync/sync_engine.dart';
import '../tx/tx_builder.dart';
import '../tx/chunk_codec.dart';
import 'package:cryptography/cryptography.dart';

class NodeConfig {
  final String? alias;
  final bool useIsarDb;
  const NodeConfig({this.alias, this.useIsarDb = true});
}

class NodeInfo {
  final String nodeId;
  final PublicIdentity keys;
  final String? alias;
  final int tipHeight;
  const NodeInfo({required this.nodeId, required this.keys, this.alias, required this.tipHeight});
}

class TxResult {
  final String txId;
  final bool ok;
  final String? error;
  const TxResult({required this.txId, required this.ok, this.error});
}

class BlockEvent {
  final BlockModel block;
  const BlockEvent(this.block);
}

class TxEvent {
  final TxModel tx;
  const TxEvent(this.tx);
}

/// PeopleChain Node facade exposing the public SDK API.
class PeopleChainNode {
  final CryptoManager _crypto;
  MessageDb? _db;
  PeerStore? _peerStore;
  P2PManager? _p2p;
  WebRtcAdapter? _webrtc;
  SyncEngine? _sync;
  TxBuilder? _txBuilder;
  NodeConfig? _config;
  CombinedKeyPairDescriptor? _desc;

  final _blockCtrl = StreamController<BlockEvent>.broadcast();
  final _txCtrl = StreamController<TxEvent>.broadcast();
  final _initCtrl = StreamController<NodeInitUpdate>.broadcast();
  final _syncStateCtrl = StreamController<SyncState>.broadcast();

  PeopleChainNode({CryptoManager? crypto}) : _crypto = crypto ?? CryptoManager();

  // region: Lifecycle
  Future<void> startNode(NodeConfig config) async {
    await _startNodeInternal(config, emitProgress: false);
  }

  /// Starts the node and emits progress updates after each internal step.
  Future<void> startNodeWithProgress(NodeConfig config) async {
    await _startNodeInternal(config, emitProgress: true);
  }

  void _emitInit(String id, String label, NodeInitStatus status, [String? error]) {
    _initCtrl.add(NodeInitUpdate(id: id, label: label, status: status, error: error));
  }

  Future<void> _startNodeInternal(NodeConfig config, {required bool emitProgress}) async {
    _config = config;
    // Step: Opening local database
    if (emitProgress) _emitInit('open_db', 'Opening local database', NodeInitStatus.inProgress);
    try {
      _db = config.useIsarDb ? await IsarMessageDb.open() : InMemoryMessageDb();
      if (emitProgress) _emitInit('open_db', 'Opening local database', NodeInitStatus.done);
    } catch (e) {
      if (emitProgress) _emitInit('open_db', 'Opening local database', NodeInitStatus.error, e.toString());
      rethrow;
    }

    // Step: Loading secure storage
    if (emitProgress) _emitInit('secure_storage', 'Loading secure storage', NodeInitStatus.inProgress);
    try {
      // Prime reads to surface storage errors early on web
      await _crypto.storage.loadSeed();
      await _crypto.storage.loadDescriptor();
      if (emitProgress) _emitInit('secure_storage', 'Loading secure storage', NodeInitStatus.done);
    } catch (e) {
      if (emitProgress) _emitInit('secure_storage', 'Loading secure storage', NodeInitStatus.error, e.toString());
      rethrow;
    }

    // Step: Generating or loading node keys
    if (emitProgress) _emitInit('ensure_keys', 'Generating or loading node keys', NodeInitStatus.inProgress);
    try {
      if (!await _crypto.hasKeys()) {
        await _crypto.generateAndStoreKeys();
      }
      _desc = await _crypto.getDescriptor();
      if (_desc == null) {
        throw StateError('Failed to initialize keys');
      }
      if (emitProgress) _emitInit('ensure_keys', 'Generating or loading node keys', NodeInitStatus.done);
    } catch (e) {
      if (emitProgress) _emitInit('ensure_keys', 'Generating or loading node keys', NodeInitStatus.error, e.toString());
      rethrow;
    }

    // Step: Preparing transaction builder
    if (emitProgress) _emitInit('tx_builder', 'Preparing transaction builder', NodeInitStatus.inProgress);
    try {
      _txBuilder = TxBuilder(crypto: _crypto, db: _db!);
      if (emitProgress) _emitInit('tx_builder', 'Preparing transaction builder', NodeInitStatus.done);
    } catch (e) {
      if (emitProgress) _emitInit('tx_builder', 'Preparing transaction builder', NodeInitStatus.error, e.toString());
      rethrow;
    }

    // Step: Ensure a lightweight genesis block exists so Chain monitors have a baseline
    if (emitProgress) _emitInit('genesis', 'Creating genesis block (if needed)', NodeInitStatus.inProgress);
    try {
      await _ensureGenesisBlock();
      if (emitProgress) _emitInit('genesis', 'Creating genesis block (if needed)', NodeInitStatus.done);
    } catch (e) {
      if (emitProgress) _emitInit('genesis', 'Creating genesis block (if needed)', NodeInitStatus.error, e.toString());
      rethrow;
    }

    // Step: Starting sync engine
    if (emitProgress) _emitInit('start_sync', 'Starting sync engine', NodeInitStatus.inProgress);
    try {
      _webrtc = WebRtcAdapter(
        nodeId: _desc!.meta.keyId,
        ed25519PubKey: _desc!.publicIdentity.ed25519,
        x25519PubKey: _desc!.publicIdentity.x25519,
        alias: config.alias,
      );
      _p2p = await P2PManager.create(
        nodeId: _desc!.meta.keyId,
        ed25519PubKey: _desc!.publicIdentity.ed25519,
        x25519PubKey: _desc!.publicIdentity.x25519,
        alias: config.alias,
        webrtc: _webrtc, // share the same adapter so manual handshakes populate the PeerStore
      );
      _peerStore = _p2p!.peerStore;

      final transport = WebRtcSyncTransport(_webrtc!);
      _sync = SyncEngine(db: _db!, crypto: _crypto, transport: transport);
      await _sync!.start();
      // Bridge events
      _sync!.onBlockAdded().listen((b) => _blockCtrl.add(BlockEvent(b)));
      _sync!.onTxReceived().listen((t) => _txCtrl.add(TxEvent(t)));
      // Initial sync state: connecting until transport opens
      _emitSyncState(SyncState.connecting);
      _webrtc!.onOpen().listen((_) {
        _emitSyncState(SyncState.handshaking);
      });
      bool movedToSynced = false;
      void promoteToSynced() {
        if (!movedToSynced) {
          movedToSynced = true;
          _emitSyncState(SyncState.synced);
        }
      }
      _sync!.onBlockAdded().listen((_) => promoteToSynced());
      _sync!.onTxReceived().listen((_) => promoteToSynced());
      if (emitProgress) _emitInit('start_sync', 'Starting sync engine', NodeInitStatus.done);
    } catch (e) {
      if (emitProgress) _emitInit('start_sync', 'Starting sync engine', NodeInitStatus.error, e.toString());
      rethrow;
    }

    // Step: Starting discovery / WebRTC services
    if (emitProgress) _emitInit('start_discovery', 'Starting discovery / WebRTC services', NodeInitStatus.inProgress);
    try {
      await _p2p!.start();
      if (emitProgress) _emitInit('start_discovery', 'Starting discovery / WebRTC services', NodeInitStatus.done);
    } catch (e) {
      if (emitProgress) {
        _emitInit('start_discovery', 'Starting discovery / WebRTC services', NodeInitStatus.error, e.toString());
      }
      rethrow;
    }
  }

  Future<void> stopNode() async {
    await _sync?.stop();
    await _p2p?.stop();
    if (_db is IsarMessageDb) {
      await (_db as IsarMessageDb).close();
    }
    await _blockCtrl.close();
    await _txCtrl.close();
  }
  // endregion

  // region: Event streams
  Stream<BlockEvent> onBlockAdded() => _blockCtrl.stream;
  Stream<TxEvent> onTxReceived() => _txCtrl.stream;
  // Surface peer discovery events from P2P manager (mDNS/BLE/WebRTC payloads)
  Stream<PeerInfo> onPeerDiscovered() => _p2p!.onPeerDiscovered();
  Stream<SyncState> onSyncState() => _syncStateCtrl.stream;
  // endregion

  // region: Info
  Future<NodeInfo> getNodeInfo() async {
    final tip = await _db!.tipHeight();
    return NodeInfo(nodeId: _desc!.meta.keyId, keys: _desc!.publicIdentity, alias: _config?.alias, tipHeight: tip);
  }
  
  Future<Map<String, dynamic>> getDiscoveryStatus() async {
    final d = _p2p?.discovery;
    if (d == null) return {'running': false};
    return d.status();
  }
  // endregion

  // region: Messaging & media
  Future<TxResult> sendMessage({required String toPubKey, required String text}) async {
    try {
      // If we know recipient x25519, encrypt text by default in production mode
      final maybeX = await _lookupX25519ForEd(toPubKey);
      final tx = (maybeX != null)
          ? await _txBuilder!.createEncryptedTextTx(toEd25519: toPubKey, toX25519: maybeX, text: text)
          : await _txBuilder!.createTextTx(toEd25519: toPubKey, text: text);
      await _sync?.announceTx(tx.txId);
      _txCtrl.add(TxEvent(tx));
      return TxResult(txId: tx.txId, ok: true);
    } catch (e) {
      return TxResult(txId: '', ok: false, error: e.toString());
    }
  }

  Future<TxResult> sendMedia({
    required String toPubKey,
    required Uint8List bytes,
    required String mime,
  }) async {
    try {
      final toX = await _lookupX25519ForEd(toPubKey);
      if (toX == null) {
        throw StateError('Recipient X25519 key unknown. Discover peer first.');
      }
      final tx = await _txBuilder!.createMediaTx(
        toEd25519: toPubKey,
        toX25519: toX,
        bytes: bytes,
        mime: mime,
      );
      await _sync?.announceTx(tx.txId);
      _txCtrl.add(TxEvent(tx));
      return TxResult(txId: tx.txId, ok: true);
    } catch (e) {
      return TxResult(txId: '', ok: false, error: e.toString());
    }
  }

  Future<List<TxModel>> getMessages({required String withPubKey, int? limit}) async {
    final me = _desc!.publicIdentity.ed25519;
    return _db!.getConversation(a: me, b: withPubKey, limit: limit);
  }
  // endregion

  // region: Decryption helpers
  /// Resolves plaintext for a text transaction. If the payload references an encrypted chunk,
  /// this will attempt to decrypt it using X25519-derived shared secret.
  Future<String?> resolveText(TxModel tx) async {
    if (tx.payload.type != 'text') {
      return '[${tx.payload.type}]';
    }
    if (tx.payload.text != null) return tx.payload.text;
    final ref = tx.payload.chunkRef;
    if (ref == null) return null;
    final chunk = await _db!.getChunk(ref);
    if (chunk?.data == null) return null;
    // Determine remote's x25519 via ed25519 mapping from PeerStore
    final other = tx.from == _desc!.publicIdentity.ed25519 ? tx.to : tx.from;
    final otherX = await _lookupX25519ForEd(other);
    if (otherX == null) return null;
    // Derive shared secret and decrypt
    final shared = await _crypto.sharedSecret(b64urlDecode(otherX));
    final participantsKey = TxBuilder.participantsKey(_desc!.publicIdentity.x25519, otherX);
    final codec = ChunkCodec();
    final clear = await codec.decrypt(
      encoded: chunk!.data!,
      sharedSecret: shared,
      participantsKey: participantsKey,
    );
    return utf8.decode(clear, allowMalformed: true);
  }
  // endregion

  // region: DB-style ops
  Future<TxModel?> getTransactionById(String txId) => _db!.getTransaction(txId);
  Future<ChunkModel?> getChunk(String chunkId) => _db!.getChunk(chunkId);
  // Blocks helpers (for monitoring/inspectors)
  Future<int> tipHeight() => _db!.tipHeight();
  Future<BlockModel?> getBlockById(String blockId) => _db!.getBlockById(blockId);
  Future<BlockModel?> getBlockByHeight(int height) => _db!.getBlockByHeight(height);
  // endregion

  // region: Key backup
  Future<List<String>> backupToShards({required int total, required int threshold}) async {
    // KeyStorage.backupToShards signature is {required int threshold, required int shares}
    return _crypto.storage.backupToShards(shares: total, threshold: threshold);
  }

  Future<void> restoreFromShards(List<String> shards) async {
    await _crypto.storage.restoreFromShards(shards);
  }
  // endregion

  // region: WebRTC QR/manual helpers
  Future<String> createOfferPayload() async {
    return _webrtc!.createOfferPayload();
  }

  Future<String> acceptOfferAndCreateAnswer(String base64OfferPayload) async {
    return _webrtc!.acceptOfferAndCreateAnswer(base64OfferPayload);
  }

  Future<void> acceptAnswer(String base64AnswerPayload) async {
    return _webrtc!.acceptAnswer(base64AnswerPayload);
  }

  /// Emits once the underlying WebRTC data channel is open.
  Stream<void> onTransportOpen() => _webrtc!.onOpen();

  /// Measures a single RTT on the transport via ping/pong test message.
  Future<Duration?> measureTransportRtt({Duration timeout = const Duration(seconds: 3)}) async {
    return _webrtc?.pingOnce(timeout: timeout);
  }

  bool get isTransportOpen => _webrtc?.isOpen ?? false;
  // endregion

  // region: Helpers
  /// Returns recently seen peers from the local peer store (in-memory on web).
  Future<List<PeerRecord>> recentPeers({int limit = 50}) async {
    return await (_peerStore?.recent(limit: limit) ?? Future.value(const <PeerRecord>[]));
  }
  Future<String?> _lookupX25519ForEd(String ed25519) async {
    // Try recent peers first
    final peers = await _peerStore?.recent(limit: 100) ?? const <PeerRecord>[];
    for (final p in peers) {
      if (p.ed25519PubKey == ed25519) return p.x25519PubKey;
    }
    // Could not resolve
    return null;
  }
  // endregion

  // region: Auto Mode & helpers
  IWebRtcAutoDiscovery? _webAuto;

  /// Enables production auto mode: automatic discovery and bootstrap on supported platforms.
  Future<void> enableAutoMode() async {
    // Web: start BroadcastChannel-based auto SDP exchange
    try {
      _webAuto ??= WebRtcBroadcastAutoDiscovery(_webrtc!);
      if (_webAuto!.isSupported) {
        await _webAuto!.start();
      }
    } catch (_) {
      // ignore
    }
  }

  void _emitSyncState(SyncState s) {
    try {
      _syncStateCtrl.add(s);
    } catch (_) {}
  }
  // endregion
}

enum NodeInitStatus { pending, inProgress, done, error }

class NodeInitUpdate {
  final String id;
  final String label;
  final NodeInitStatus status;
  final String? error;
  const NodeInitUpdate({
    required this.id,
    required this.label,
    required this.status,
    this.error,
  });
}

extension PeopleChainNodeInit on PeopleChainNode {
  Stream<NodeInitUpdate> onInitProgress() => _initCtrl.stream;
}

// region: Private helpers
extension _Genesis on PeopleChainNode {
  Future<void> _ensureGenesisBlock() async {
    final tip = await _db!.tipHeight();
    if (tip >= 0) return; // exists
    final desc = await _crypto.getDescriptor();
    if (desc == null) {
      throw StateError('No key descriptor available for genesis');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final proposer = desc.publicIdentity.ed25519;
    // Deterministic-ish id seed using node id + timestamp to avoid collisions across sessions
    final seed = utf8.encode('genesis|${desc.meta.keyId}|$now');
    final d = await Sha256().hash(seed);
    final id = b64url(Uint8List.fromList(d.bytes));
    final header = BlockHeaderModel(
      blockId: id,
      height: 0,
      prevBlockId: '',
      timestampMs: now,
      txMerkleRoot: '',
      proposer: proposer,
    );
    final block = BlockModel(header: header, txIds: const [], signatures: const []);
    await _db!.putBlock(block);
    // Surface to listeners so monitors update immediately
    _blockCtrl.add(BlockEvent(block));
  }
}
// endregion

enum SyncState { connecting, handshaking, synced }
