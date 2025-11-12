// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'isar_models.dart';

// coverage:ignore-file

final ChunkEntitySchema = CollectionSchema(
  name: r'ChunkEntity',
  // Use web-safe small integer for schema id (unique)
  id: 1001,
  properties: {
    r'chunkId': PropertySchema(id: 0, name: r'chunkId', type: IsarType.string),
    r'type': PropertySchema(id: 1, name: r'type', type: IsarType.string),
    r'sizeBytes': PropertySchema(id: 2, name: r'sizeBytes', type: IsarType.long),
    r'hash': PropertySchema(id: 3, name: r'hash', type: IsarType.string),
    r'data': PropertySchema(id: 4, name: r'data', type: IsarType.byteList),
    r'mime': PropertySchema(id: 5, name: r'mime', type: IsarType.string),
  },
  estimateSize: _chunkEntityEstimateSize,
  serialize: _chunkEntitySerialize,
  deserialize: _chunkEntityDeserialize,
  deserializeProp: _chunkEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'chunkId': IndexSchema(
      // Web-safe unique index id
      id: 2001,
      name: r'chunkId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(name: r'chunkId', type: IndexType.hash, caseSensitive: true),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _chunkEntityGetId,
  getLinks: _chunkEntityGetLinks,
  attach: _chunkEntityAttach,
  // Match the runtime Isar.version (e.g., 3.1.0+1) to avoid web assertion failures
  version: Isar.version,
);

int _chunkEntityEstimateSize(ChunkEntity object, List<int> offsets, Map<Type, List<int>> allOffsets) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.chunkId.length * 3;
  bytesCount += 3 + object.type.length * 3;
  bytesCount += 8;
  bytesCount += 3 + object.hash.length * 3;
  final data = object.data;
  if (data != null) {
    bytesCount += 3 + data.length;
  }
  final mime = object.mime;
  if (mime != null) {
    bytesCount += 3 + mime.length * 3;
  }
  return bytesCount;
}

void _chunkEntitySerialize(ChunkEntity object, IsarWriter writer, List<int> offsets, Map<Type, List<int>> allOffsets) {
  writer.writeString(offsets[0], object.chunkId);
  writer.writeString(offsets[1], object.type);
  writer.writeLong(offsets[2], object.sizeBytes);
  writer.writeString(offsets[3], object.hash);
  writer.writeByteList(offsets[4], object.data);
  writer.writeString(offsets[5], object.mime);
}

ChunkEntity _chunkEntityDeserialize(Id id, IsarReader reader, List<int> offsets, Map<Type, List<int>> allOffsets) {
  final object = ChunkEntity();
  object.id = id;
  object.chunkId = reader.readString(offsets[0])!;
  object.type = reader.readString(offsets[1])!;
  object.sizeBytes = reader.readLong(offsets[2])!;
  object.hash = reader.readString(offsets[3])!;
  object.data = reader.readByteList(offsets[4]);
  object.mime = reader.readString(offsets[5]);
  return object;
}

P _chunkEntityDeserializeProp<P>(IsarReader reader, int propertyId, int offset, Map<Type, List<int>> allOffsets) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readByteList(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _chunkEntityGetId(ChunkEntity object) => object.id;

List<IsarLinkBase> _chunkEntityGetLinks(ChunkEntity object) => const [];

void _chunkEntityAttach(IsarCollection<ChunkEntity> col, Id id, ChunkEntity object) {
  object.id = id;
}

// TxEntity
final TxEntitySchema = CollectionSchema(
  name: r'TxEntity',
  // Web-safe schema id
  id: 1002,
  properties: {
    r'txId': PropertySchema(id: 0, name: r'txId', type: IsarType.string),
    r'from': PropertySchema(id: 1, name: r'from', type: IsarType.string),
    r'to': PropertySchema(id: 2, name: r'to', type: IsarType.string),
    r'nonce': PropertySchema(id: 3, name: r'nonce', type: IsarType.long),
    r'timestampMs': PropertySchema(id: 4, name: r'timestampMs', type: IsarType.long),
    r'participantsKey': PropertySchema(id: 5, name: r'participantsKey', type: IsarType.string),
    r'payloadType': PropertySchema(id: 6, name: r'payloadType', type: IsarType.string),
    r'payloadText': PropertySchema(id: 7, name: r'payloadText', type: IsarType.string),
    r'payloadChunkRef': PropertySchema(id: 8, name: r'payloadChunkRef', type: IsarType.string),
    r'payloadMime': PropertySchema(id: 9, name: r'payloadMime', type: IsarType.string),
    r'payloadSizeBytes': PropertySchema(id: 10, name: r'payloadSizeBytes', type: IsarType.long),
    r'signature': PropertySchema(id: 11, name: r'signature', type: IsarType.string),
  },
  estimateSize: _txEntityEstimateSize,
  serialize: _txEntitySerialize,
  deserialize: _txEntityDeserialize,
  deserializeProp: _txEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'txId': IndexSchema(
      id: 2002,
      name: r'txId',
      unique: true,
      replace: true,
      properties: [IndexPropertySchema(name: r'txId', type: IndexType.hash, caseSensitive: true)],
    ),
    r'participants_timestamp': IndexSchema(
      id: 2003,
      name: r'participants_timestamp',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(name: r'participantsKey', type: IndexType.hash, caseSensitive: true),
        IndexPropertySchema(name: r'timestampMs', type: IndexType.value, caseSensitive: false),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _txEntityGetId,
  getLinks: _txEntityGetLinks,
  attach: _txEntityAttach,
  // Use runtime Isar.version for compatibility with patch releases
  version: Isar.version,
);

int _txEntityEstimateSize(TxEntity object, List<int> offsets, Map<Type, List<int>> allOffsets) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.txId.length * 3;
  bytesCount += 3 + object.from.length * 3;
  bytesCount += 3 + object.to.length * 3;
  bytesCount += 8; // nonce
  bytesCount += 8; // timestamp
  bytesCount += 3 + object.participantsKey.length * 3;
  bytesCount += 3 + object.payloadType.length * 3;
  final t = object.payloadText; if (t != null) { bytesCount += 3 + t.length * 3; }
  final cr = object.payloadChunkRef; if (cr != null) { bytesCount += 3 + cr.length * 3; }
  final pm = object.payloadMime; if (pm != null) { bytesCount += 3 + pm.length * 3; }
  bytesCount += 8; // size bytes
  bytesCount += 3 + object.signature.length * 3;
  return bytesCount;
}

void _txEntitySerialize(TxEntity object, IsarWriter writer, List<int> offsets, Map<Type, List<int>> allOffsets) {
  writer.writeString(offsets[0], object.txId);
  writer.writeString(offsets[1], object.from);
  writer.writeString(offsets[2], object.to);
  writer.writeLong(offsets[3], object.nonce);
  writer.writeLong(offsets[4], object.timestampMs);
  writer.writeString(offsets[5], object.participantsKey);
  writer.writeString(offsets[6], object.payloadType);
  writer.writeString(offsets[7], object.payloadText);
  writer.writeString(offsets[8], object.payloadChunkRef);
  writer.writeString(offsets[9], object.payloadMime);
  writer.writeLong(offsets[10], object.payloadSizeBytes);
  writer.writeString(offsets[11], object.signature);
}

TxEntity _txEntityDeserialize(Id id, IsarReader reader, List<int> offsets, Map<Type, List<int>> allOffsets) {
  final object = TxEntity();
  object.id = id;
  object.txId = reader.readString(offsets[0])!;
  object.from = reader.readString(offsets[1])!;
  object.to = reader.readString(offsets[2])!;
  object.nonce = reader.readLong(offsets[3])!;
  object.timestampMs = reader.readLong(offsets[4])!;
  object.participantsKey = reader.readString(offsets[5])!;
  object.payloadType = reader.readString(offsets[6])!;
  object.payloadText = reader.readString(offsets[7]);
  object.payloadChunkRef = reader.readString(offsets[8]);
  object.payloadMime = reader.readString(offsets[9]);
  object.payloadSizeBytes = reader.readLong(offsets[10]) ?? 0;
  object.signature = reader.readString(offsets[11])!;
  return object;
}

P _txEntityDeserializeProp<P>(IsarReader reader, int propertyId, int offset, Map<Type, List<int>> allOffsets) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readLong(offset)) as P;
    case 11:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _txEntityGetId(TxEntity object) => object.id;

List<IsarLinkBase> _txEntityGetLinks(TxEntity object) => const [];

void _txEntityAttach(IsarCollection<TxEntity> col, Id id, TxEntity object) {
  object.id = id;
}

// BlockEntity
final BlockEntitySchema = CollectionSchema(
  name: r'BlockEntity',
  id: 1003,
  properties: {
    r'blockId': PropertySchema(id: 0, name: r'blockId', type: IsarType.string),
    r'height': PropertySchema(id: 1, name: r'height', type: IsarType.long),
    r'prevBlockId': PropertySchema(id: 2, name: r'prevBlockId', type: IsarType.string),
    r'timestampMs': PropertySchema(id: 3, name: r'timestampMs', type: IsarType.long),
    r'txMerkleRoot': PropertySchema(id: 4, name: r'txMerkleRoot', type: IsarType.string),
    r'proposer': PropertySchema(id: 5, name: r'proposer', type: IsarType.string),
    r'txIds': PropertySchema(id: 6, name: r'txIds', type: IsarType.stringList),
    r'signatures': PropertySchema(id: 7, name: r'signatures', type: IsarType.stringList),
  },
  estimateSize: _blockEntityEstimateSize,
  serialize: _blockEntitySerialize,
  deserialize: _blockEntityDeserialize,
  deserializeProp: _blockEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'blockId': IndexSchema(
      id: 2004,
      name: r'blockId',
      unique: true,
      replace: true,
      properties: [IndexPropertySchema(name: r'blockId', type: IndexType.hash, caseSensitive: true)],
    ),
    r'height': IndexSchema(
      id: 2005,
      name: r'height',
      unique: true,
      replace: true,
      properties: [IndexPropertySchema(name: r'height', type: IndexType.value, caseSensitive: false)],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _blockEntityGetId,
  getLinks: _blockEntityGetLinks,
  attach: _blockEntityAttach,
  version: Isar.version,
);

int _blockEntityEstimateSize(BlockEntity object, List<int> offsets, Map<Type, List<int>> allOffsets) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.blockId.length * 3;
  bytesCount += 8; // height
  bytesCount += 3 + object.prevBlockId.length * 3;
  bytesCount += 8; // timestamp
  bytesCount += 3 + object.txMerkleRoot.length * 3;
  bytesCount += 3 + object.proposer.length * 3;
  var txCount = object.txIds.length;
  bytesCount += 3 + txCount * 3;
  for (final s in object.txIds) {
    bytesCount += s.length * 3;
  }
  var sigCount = object.signatures.length;
  bytesCount += 3 + sigCount * 3;
  for (final s in object.signatures) {
    bytesCount += s.length * 3;
  }
  return bytesCount;
}

void _blockEntitySerialize(BlockEntity object, IsarWriter writer, List<int> offsets, Map<Type, List<int>> allOffsets) {
  writer.writeString(offsets[0], object.blockId);
  writer.writeLong(offsets[1], object.height);
  writer.writeString(offsets[2], object.prevBlockId);
  writer.writeLong(offsets[3], object.timestampMs);
  writer.writeString(offsets[4], object.txMerkleRoot);
  writer.writeString(offsets[5], object.proposer);
  writer.writeStringList(offsets[6], object.txIds);
  writer.writeStringList(offsets[7], object.signatures);
}

BlockEntity _blockEntityDeserialize(Id id, IsarReader reader, List<int> offsets, Map<Type, List<int>> allOffsets) {
  final object = BlockEntity();
  object.id = id;
  object.blockId = reader.readString(offsets[0])!;
  object.height = reader.readLong(offsets[1])!;
  object.prevBlockId = reader.readString(offsets[2])!;
  object.timestampMs = reader.readLong(offsets[3])!;
  object.txMerkleRoot = reader.readString(offsets[4])!;
  object.proposer = reader.readString(offsets[5])!;
  object.txIds = reader.readStringList(offsets[6]) ?? const [];
  object.signatures = reader.readStringList(offsets[7]) ?? const [];
  return object;
}

P _blockEntityDeserializeProp<P>(IsarReader reader, int propertyId, int offset, Map<Type, List<int>> allOffsets) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readStringList(offset)) as P;
    case 7:
      return (reader.readStringList(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _blockEntityGetId(BlockEntity object) => object.id;

List<IsarLinkBase> _blockEntityGetLinks(BlockEntity object) => const [];

void _blockEntityAttach(IsarCollection<BlockEntity> col, Id id, BlockEntity object) {
  object.id = id;
}

// ConversationEntity
final ConversationEntitySchema = CollectionSchema(
  name: r'ConversationEntity',
  id: 1004,
  properties: {
    r'key': PropertySchema(id: 0, name: r'key', type: IsarType.string),
    r'txRefs': PropertySchema(id: 1, name: r'txRefs', type: IsarType.stringList),
  },
  estimateSize: _conversationEntityEstimateSize,
  serialize: _conversationEntitySerialize,
  deserialize: _conversationEntityDeserialize,
  deserializeProp: _conversationEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'key': IndexSchema(
      id: 2006,
      name: r'key',
      unique: true,
      replace: true,
      properties: [IndexPropertySchema(name: r'key', type: IndexType.hash, caseSensitive: true)],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _conversationEntityGetId,
  getLinks: _conversationEntityGetLinks,
  attach: _conversationEntityAttach,
  version: Isar.version,
);

int _conversationEntityEstimateSize(ConversationEntity object, List<int> offsets, Map<Type, List<int>> allOffsets) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.key.length * 3;
  var count = object.txRefs.length;
  bytesCount += 3 + count * 3;
  for (final s in object.txRefs) {
    bytesCount += s.length * 3;
  }
  return bytesCount;
}

void _conversationEntitySerialize(ConversationEntity object, IsarWriter writer, List<int> offsets, Map<Type, List<int>> allOffsets) {
  writer.writeString(offsets[0], object.key);
  writer.writeStringList(offsets[1], object.txRefs);
}

ConversationEntity _conversationEntityDeserialize(Id id, IsarReader reader, List<int> offsets, Map<Type, List<int>> allOffsets) {
  final object = ConversationEntity();
  object.id = id;
  object.key = reader.readString(offsets[0])!;
  object.txRefs = reader.readStringList(offsets[1]) ?? const [];
  return object;
}

P _conversationEntityDeserializeProp<P>(IsarReader reader, int propertyId, int offset, Map<Type, List<int>> allOffsets) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readStringList(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _conversationEntityGetId(ConversationEntity object) => object.id;

List<IsarLinkBase> _conversationEntityGetLinks(ConversationEntity object) => const [];

void _conversationEntityAttach(IsarCollection<ConversationEntity> col, Id id, ConversationEntity object) {
  object.id = id;
}
  
  // PeerEntity
  final PeerEntitySchema = CollectionSchema(
    name: r'PeerEntity',
    id: 1005,
    properties: {
      r'nodeId': PropertySchema(id: 0, name: r'nodeId', type: IsarType.string),
      r'alias': PropertySchema(id: 1, name: r'alias', type: IsarType.string),
      r'ed25519PubKey': PropertySchema(id: 2, name: r'ed25519PubKey', type: IsarType.string),
      r'x25519PubKey': PropertySchema(id: 3, name: r'x25519PubKey', type: IsarType.string),
      r'lastSeenMs': PropertySchema(id: 4, name: r'lastSeenMs', type: IsarType.long),
      r'transports': PropertySchema(id: 5, name: r'transports', type: IsarType.stringList),
    },
    estimateSize: _peerEntityEstimateSize,
    serialize: _peerEntitySerialize,
    deserialize: _peerEntityDeserialize,
    deserializeProp: _peerEntityDeserializeProp,
    idName: r'id',
    indexes: {
      r'nodeId': IndexSchema(
        id: 2007,
        name: r'nodeId',
        unique: true,
        replace: true,
        properties: [IndexPropertySchema(name: r'nodeId', type: IndexType.hash, caseSensitive: true)],
      ),
      r'lastSeenMs': IndexSchema(
        id: 2008,
        name: r'lastSeenMs',
        unique: false,
        replace: false,
        properties: [IndexPropertySchema(name: r'lastSeenMs', type: IndexType.value, caseSensitive: false)],
      ),
    },
    links: {},
    embeddedSchemas: {},
    getId: _peerEntityGetId,
    getLinks: _peerEntityGetLinks,
    attach: _peerEntityAttach,
    version: Isar.version,
  );

  int _peerEntityEstimateSize(PeerEntity object, List<int> offsets, Map<Type, List<int>> allOffsets) {
    var bytesCount = offsets.last;
    bytesCount += 3 + object.nodeId.length * 3;
    final a = object.alias; if (a != null) { bytesCount += 3 + a.length * 3; }
    bytesCount += 3 + object.ed25519PubKey.length * 3;
    bytesCount += 3 + object.x25519PubKey.length * 3;
    bytesCount += 8; // lastSeenMs
    final t = object.transports; bytesCount += 3 + t.length * 3; for (final s in t) { bytesCount += s.length * 3; }
    return bytesCount;
  }

  void _peerEntitySerialize(PeerEntity object, IsarWriter writer, List<int> offsets, Map<Type, List<int>> allOffsets) {
    writer.writeString(offsets[0], object.nodeId);
    writer.writeString(offsets[1], object.alias);
    writer.writeString(offsets[2], object.ed25519PubKey);
    writer.writeString(offsets[3], object.x25519PubKey);
    writer.writeLong(offsets[4], object.lastSeenMs);
    writer.writeStringList(offsets[5], object.transports);
  }

  PeerEntity _peerEntityDeserialize(Id id, IsarReader reader, List<int> offsets, Map<Type, List<int>> allOffsets) {
    final object = PeerEntity();
    object.id = id;
    object.nodeId = reader.readString(offsets[0])!;
    object.alias = reader.readString(offsets[1]);
    object.ed25519PubKey = reader.readString(offsets[2])!;
    object.x25519PubKey = reader.readString(offsets[3])!;
    object.lastSeenMs = reader.readLong(offsets[4]) ?? 0;
    object.transports = reader.readStringList(offsets[5]) ?? const [];
    return object;
  }

  P _peerEntityDeserializeProp<P>(IsarReader reader, int propertyId, int offset, Map<Type, List<int>> allOffsets) {
    switch (propertyId) {
      case 0:
        return (reader.readString(offset)) as P;
      case 1:
        return (reader.readString(offset)) as P;
      case 2:
        return (reader.readString(offset)) as P;
      case 3:
        return (reader.readString(offset)) as P;
      case 4:
        return (reader.readLong(offset)) as P;
      case 5:
        return (reader.readStringList(offset)) as P;
      default:
        throw IsarError('Unknown property with id $propertyId');
    }
  }

  Id _peerEntityGetId(PeerEntity object) => object.id;

  List<IsarLinkBase> _peerEntityGetLinks(PeerEntity object) => const [];

  void _peerEntityAttach(IsarCollection<PeerEntity> col, Id id, PeerEntity object) {
    object.id = id;
  }
