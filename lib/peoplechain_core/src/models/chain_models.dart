import 'dart:convert';
import 'dart:typed_data';

// Chain Manifest
class ChainManifestModel {
  final String chainId;
  final String version;
  final DateTime genesisTime;
  final int blockTimeTargetMs;
  final int maxBlockSizeBytes;
  final String hashAlgorithm; // sha256 | blake3
  final List<String> encryptionAlgorithms; // xchacha20poly1305 | aes-gcm | none
  final String compression; // none | zstd
  final String consensusType; // pow | pos | poa | dpos
  final Map<String, dynamic>? consensusParams;

  const ChainManifestModel({
    required this.chainId,
    required this.version,
    required this.genesisTime,
    required this.blockTimeTargetMs,
    required this.maxBlockSizeBytes,
    required this.hashAlgorithm,
    required this.encryptionAlgorithms,
    required this.compression,
    required this.consensusType,
    this.consensusParams,
  });

  Map<String, dynamic> toJson() => {
        'chain_id': chainId,
        'version': version,
        'genesis_time': genesisTime.toIso8601String(),
        'block_time_target_ms': blockTimeTargetMs,
        'max_block_size_bytes': maxBlockSizeBytes,
        'hash_algorithm': hashAlgorithm,
        'encryption_algorithms': encryptionAlgorithms,
        'compression': compression,
        'consensus': {
          'type': consensusType,
          if (consensusParams != null) 'params': consensusParams,
        }
      };

  factory ChainManifestModel.fromJson(Map<String, dynamic> json) => ChainManifestModel(
        chainId: json['chain_id'] as String,
        version: json['version'] as String,
        genesisTime: DateTime.parse(json['genesis_time'] as String),
        blockTimeTargetMs: json['block_time_target_ms'] as int,
        maxBlockSizeBytes: json['max_block_size_bytes'] as int,
        hashAlgorithm: json['hash_algorithm'] as String,
        encryptionAlgorithms:
            (json['encryption_algorithms'] as List).map((e) => e as String).toList(),
        compression: json['compression'] as String,
        consensusType: (json['consensus'] as Map<String, dynamic>)['type'] as String,
        consensusParams: (json['consensus'] as Map<String, dynamic>)['params']
            as Map<String, dynamic>?,
      );
}

// Node Record
class NodeRecordModel {
  final String nodeId;
  final String userId;
  final String ed25519;
  final String x25519;
  final List<String> addresses;
  final List<String> capabilities;
  final Map<String, dynamic>? metadata;

  const NodeRecordModel({
    required this.nodeId,
    required this.userId,
    required this.ed25519,
    required this.x25519,
    required this.addresses,
    this.capabilities = const [],
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'node_id': nodeId,
        'user_id': userId,
        'public_keys': {'ed25519': ed25519, 'x25519': x25519},
        'network': {'addresses': addresses, 'capabilities': capabilities},
        if (metadata != null) 'metadata': metadata,
      };

  factory NodeRecordModel.fromJson(Map<String, dynamic> json) => NodeRecordModel(
        nodeId: json['node_id'] as String,
        userId: json['user_id'] as String,
        ed25519: (json['public_keys'] as Map<String, dynamic>)['ed25519'] as String,
        x25519: (json['public_keys'] as Map<String, dynamic>)['x25519'] as String,
        addresses:
            ((json['network'] as Map<String, dynamic>)['addresses'] as List).map((e) => e as String).toList(),
        capabilities: ((json['network'] as Map<String, dynamic>)['capabilities'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

// Chunk
class ChunkModel {
  final String chunkId; // hash/id
  final String type; // text | media | file
  final int sizeBytes;
  final String hash; // content hash
  final Uint8List? data; // optional inline for small payloads
  final String? mime;

  const ChunkModel({
    required this.chunkId,
    required this.type,
    required this.sizeBytes,
    required this.hash,
    this.data,
    this.mime,
  });

  Map<String, dynamic> toJson() => {
        'chunk_id': chunkId,
        'type': type,
        'size_bytes': sizeBytes,
        'hash': hash,
        if (data != null) 'data_b64': base64Encode(data!),
        if (mime != null) 'mime': mime,
      };

  factory ChunkModel.fromJson(Map<String, dynamic> json) => ChunkModel(
        chunkId: json['chunk_id'] as String,
        type: json['type'] as String,
        sizeBytes: json['size_bytes'] as int,
        hash: json['hash'] as String,
        data: (json['data_b64'] as String?) != null
            ? Uint8List.fromList(base64Decode(json['data_b64'] as String))
            : null,
        mime: json['mime'] as String?,
      );
}

// Transaction
class TxPayloadModel {
  final String type; // text | media | file
  final String? text;
  final String? chunkRef;
  final String? mime;
  final int? sizeBytes;

  const TxPayloadModel({
    required this.type,
    this.text,
    this.chunkRef,
    this.mime,
    this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        if (text != null) 'text': text,
        if (chunkRef != null) 'chunk_ref': chunkRef,
        if (mime != null) 'mime': mime,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
      };

  factory TxPayloadModel.fromJson(Map<String, dynamic> json) => TxPayloadModel(
        type: json['type'] as String,
        text: json['text'] as String?,
        chunkRef: json['chunk_ref'] as String?,
        mime: json['mime'] as String?,
        sizeBytes: json['size_bytes'] as int?,
      );
}

class TxModel {
  final String txId;
  final String from;
  final String to;
  final int nonce;
  final int timestampMs;
  final TxPayloadModel payload;
  final String signature; // base64url

  const TxModel({
    required this.txId,
    required this.from,
    required this.to,
    required this.nonce,
    required this.timestampMs,
    required this.payload,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'tx_id': txId,
        'from': from,
        'to': to,
        'nonce': nonce,
        'timestamp_ms': timestampMs,
        'payload': payload.toJson(),
        'signature': signature,
      };

  factory TxModel.fromJson(Map<String, dynamic> json) => TxModel(
        txId: json['tx_id'] as String,
        from: json['from'] as String,
        to: json['to'] as String,
        nonce: json['nonce'] as int,
        timestampMs: json['timestamp_ms'] as int,
        payload: TxPayloadModel.fromJson(json['payload'] as Map<String, dynamic>),
        signature: json['signature'] as String,
      );
}

// Block
class BlockHeaderModel {
  final String blockId;
  final int height;
  final String prevBlockId;
  final int timestampMs;
  final String txMerkleRoot;
  final String proposer;

  const BlockHeaderModel({
    required this.blockId,
    required this.height,
    required this.prevBlockId,
    required this.timestampMs,
    required this.txMerkleRoot,
    required this.proposer,
  });

  Map<String, dynamic> toJson() => {
        'block_id': blockId,
        'height': height,
        'prev_block_id': prevBlockId,
        'timestamp_ms': timestampMs,
        'tx_merkle_root': txMerkleRoot,
        'proposer': proposer,
      };

  factory BlockHeaderModel.fromJson(Map<String, dynamic> json) => BlockHeaderModel(
        blockId: json['block_id'] as String,
        height: json['height'] as int,
        prevBlockId: json['prev_block_id'] as String,
        timestampMs: json['timestamp_ms'] as int,
        txMerkleRoot: json['tx_merkle_root'] as String,
        proposer: json['proposer'] as String,
      );
}

class BlockSignatureModel {
  final String signer;
  final String signature;
  const BlockSignatureModel({required this.signer, required this.signature});

  Map<String, dynamic> toJson() => {'signer': signer, 'signature': signature};

  factory BlockSignatureModel.fromJson(Map<String, dynamic> json) =>
      BlockSignatureModel(signer: json['signer'] as String, signature: json['signature'] as String);
}

class BlockModel {
  final BlockHeaderModel header;
  final List<String> txIds;
  final List<BlockSignatureModel> signatures;

  const BlockModel({required this.header, required this.txIds, required this.signatures});

  Map<String, dynamic> toJson() => {
        'header': header.toJson(),
        'tx_ids': txIds,
        'signatures': signatures.map((e) => e.toJson()).toList(),
      };

  factory BlockModel.fromJson(Map<String, dynamic> json) => BlockModel(
        header: BlockHeaderModel.fromJson(json['header'] as Map<String, dynamic>),
        txIds: (json['tx_ids'] as List).map((e) => e as String).toList(),
        signatures: (json['signatures'] as List)
            .map((e) => BlockSignatureModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// Checkpoint
class CheckpointModel {
  final int height;
  final String blockId;
  final String stateRoot;
  final int timestampMs;

  const CheckpointModel({
    required this.height,
    required this.blockId,
    required this.stateRoot,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'height': height,
        'block_id': blockId,
        'state_root': stateRoot,
        'timestamp_ms': timestampMs,
      };

  factory CheckpointModel.fromJson(Map<String, dynamic> json) => CheckpointModel(
        height: json['height'] as int,
        blockId: json['block_id'] as String,
        stateRoot: json['state_root'] as String,
        timestampMs: json['timestamp_ms'] as int,
      );
}
