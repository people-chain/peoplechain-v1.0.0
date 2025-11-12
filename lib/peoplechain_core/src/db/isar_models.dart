import 'package:isar/isar.dart';

part 'isar_models.g.dart';

class ChunkEntity {
  Id id = Isar.autoIncrement;
  late String chunkId; // unique
  late String type;
  late int sizeBytes;
  late String hash;
  List<int>? data;
  String? mime;
}

class TxEntity {
  Id id = Isar.autoIncrement;
  late String txId; // unique
  late String from;
  late String to;
  late int nonce;
  late int timestampMs;
  late String participantsKey; // sorted a|b, indexed with timestamp

  // payload
  late String payloadType;
  String? payloadText;
  String? payloadChunkRef;
  String? payloadMime;
  int payloadSizeBytes = 0;

  late String signature;
}

class BlockEntity {
  Id id = Isar.autoIncrement;
  late String blockId; // unique
  late int height; // unique index
  late String prevBlockId;
  late int timestampMs;
  late String txMerkleRoot;
  late String proposer;

  List<String> txIds = const [];
  List<String> signatures = const []; // encoded as signer|signature
}

class ConversationEntity {
  Id id = Isar.autoIncrement;
  late String key; // participantsKey, unique
  List<String> txRefs = const []; // sorted by asc timestamp, format: tttttttttttttttt:txId
}

/// Known peer metadata stored locally.
/// Minimal fields to support discovery and recency queries.
class PeerEntity {
  Id id = Isar.autoIncrement;
  late String nodeId; // unique
  String? alias;
  late String ed25519PubKey;
  late String x25519PubKey;
  int lastSeenMs = 0;
  List<String> transports = const []; // e.g., ['webrtc','mdns','ble']
}
