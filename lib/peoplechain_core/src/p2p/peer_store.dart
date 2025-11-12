import 'package:isar/isar.dart';

import '../db/isar_factory.dart';
import '../db/isar_models.dart';

class PeerRecord {
  final String nodeId;
  final String ed25519PubKey;
  final String x25519PubKey;
  final int lastSeenMs;
  final List<String> transports;
  final String? alias;

  const PeerRecord({
    required this.nodeId,
    required this.ed25519PubKey,
    required this.x25519PubKey,
    required this.lastSeenMs,
    this.transports = const [],
    this.alias,
  });
}

abstract class PeerStore {
  Future<void> putOrUpdate(PeerRecord peer);
  Future<PeerRecord?> getByNodeId(String nodeId);
  Future<List<PeerRecord>> recent({int limit = 50});
  Future<void> markSeen(String nodeId, int timestampMs);
}

class IsarPeerStore implements PeerStore {
  final Isar _isar;
  IsarPeerStore._(this._isar);

  static Future<IsarPeerStore> open({String? directoryPath, String name = 'peoplechain'}) async {
    final isar = await IsarFactory.open(directoryPath: directoryPath, name: name);
    return IsarPeerStore._(isar);
  }

  @override
  Future<PeerRecord?> getByNodeId(String nodeId) async {
    final e = await _isar.collection<PeerEntity>().getByIndex('nodeId', [nodeId]);
    if (e == null) return null;
    return _toRecord(e);
  }

  @override
  Future<void> markSeen(String nodeId, int timestampMs) async {
    await _isar.writeTxn(() async {
      final e = await _isar.collection<PeerEntity>().getByIndex('nodeId', [nodeId]);
      if (e != null) {
        e.lastSeenMs = timestampMs;
        await _isar.collection<PeerEntity>().putByIndex('nodeId', e);
      }
    });
  }

  @override
  Future<void> putOrUpdate(PeerRecord peer) async {
    final e = PeerEntity()
      ..nodeId = peer.nodeId
      ..alias = peer.alias
      ..ed25519PubKey = peer.ed25519PubKey
      ..x25519PubKey = peer.x25519PubKey
      ..lastSeenMs = peer.lastSeenMs
      ..transports = peer.transports;
    await _isar.writeTxn(() async {
      await _isar.collection<PeerEntity>().putByIndex('nodeId', e);
    });
  }

  @override
  Future<List<PeerRecord>> recent({int limit = 50}) async {
    // Isar doesn't support ordering by index directly via codegen-free API, so scan reasonable range.
    final col = _isar.collection<PeerEntity>();
    // Simple approach: get all, sort in memory. For small peer sets this is fine.
    final allIds = await col.where().findAll();
    allIds.sort((a, b) => b.lastSeenMs.compareTo(a.lastSeenMs));
    final list = allIds.take(limit).map(_toRecord).toList();
    return list;
  }

  PeerRecord _toRecord(PeerEntity e) => PeerRecord(
        nodeId: e.nodeId,
        ed25519PubKey: e.ed25519PubKey,
        x25519PubKey: e.x25519PubKey,
        lastSeenMs: e.lastSeenMs,
        transports: e.transports,
        alias: e.alias,
      );
}

/// Simple in-memory PeerStore for web where Isar 3.x has no web support.
class InMemoryPeerStore implements PeerStore {
  final Map<String, PeerRecord> _byNodeId = {};

  @override
  Future<PeerRecord?> getByNodeId(String nodeId) async => _byNodeId[nodeId];

  @override
  Future<void> markSeen(String nodeId, int timestampMs) async {
    final existing = _byNodeId[nodeId];
    if (existing != null) {
      _byNodeId[nodeId] = PeerRecord(
        nodeId: existing.nodeId,
        ed25519PubKey: existing.ed25519PubKey,
        x25519PubKey: existing.x25519PubKey,
        lastSeenMs: timestampMs,
        transports: existing.transports,
        alias: existing.alias,
      );
    }
  }

  @override
  Future<void> putOrUpdate(PeerRecord peer) async {
    _byNodeId[peer.nodeId] = peer;
  }

  @override
  Future<List<PeerRecord>> recent({int limit = 50}) async {
    final list = _byNodeId.values.toList()
      ..sort((a, b) => b.lastSeenMs.compareTo(a.lastSeenMs));
    if (list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }
}
