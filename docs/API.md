PeopleChain Core SDK — API Reference (Updated)

Package: peoplechain_core

Overview
- Fully on-device decentralized chat ledger with P2P sync. Works on Android, iOS, and Web.
- Public entrypoint: import 'package:peoplechain_core/peoplechain_core.dart'

Key Namespaces and Types

1) PeopleChainNode (SDK facade)
- Lifecycle
  - Future<void> startNode(NodeConfig config)
  - Future<void> stopNode()
- Info
  - Future<NodeInfo> getNodeInfo()
- Events
  - Stream<BlockEvent> onBlockAdded()
  - Stream<TxEvent> onTxReceived()
- Messaging & media
  - Future<TxResult> sendMessage({required String toPubKey, required String text})
  - Future<TxResult> sendMedia({required String toPubKey, required Uint8List bytes, required String mime})
  - Future<List<TxModel>> getMessages({required String withPubKey, int? limit})
- DB-style ops
  - Future<TxModel?> getTransactionById(String txId)
  - Future<ChunkModel?> getChunk(String chunkId)
- Key backup
  - Future<List<String>> backupToShards({required int total, required int threshold})
  - Future<void> restoreFromShards(List<String> shards)
 - WebRTC manual/QR bootstrap
  - Future<String> createOfferPayload()
  - Future<String> acceptOfferAndCreateAnswer(String base64OfferPayload)
  - Future<void> acceptAnswer(String base64AnswerPayload)

2) Supporting data types
- NodeConfig
  - const NodeConfig({String? alias, bool useIsarDb = true})
- NodeInfo
  - nodeId: String
  - keys: PublicIdentity { ed25519, x25519 }
  - alias: String?
  - tipHeight: int
- TxResult { txId, ok, error? }
- BlockEvent { block: BlockModel }
- TxEvent { tx: TxModel }

3) Models (serialize to/from JSON)
- PublicIdentity { ed25519, x25519 }
- CombinedKeyPairDescriptor { publicIdentity, meta { keyId, createdAt } }
- ChunkModel { chunkId, type, sizeBytes, hash, data?, mime? }
- TxPayloadModel { type, text?, chunkRef?, mime?, sizeBytes? }
- TxModel { txId, from, to, nonce, timestampMs, payload, signature }
- BlockHeaderModel { blockId, height, prevBlockId, timestampMs, txMerkleRoot, proposer }
- BlockSignatureModel { signer, signature }
- BlockModel { header, txIds, signatures }

4) CryptoManager (low-level cryptography)
- bool hasKeys()
- Future<CombinedKeyPairDescriptor> generateAndStoreKeys()
- Future<CombinedKeyPairDescriptor?> getDescriptor()
- Future<Uint8List> sign(Uint8List message)
- Future<bool> verify({required Uint8List message, required Uint8List signature, required Uint8List publicKey})
- Future<Uint8List> sharedSecret(Uint8List remoteX25519PublicKey)

5) Storage APIs
- MessageDb (abstract) with IsarMessageDb implementation
  - putChunk/getChunk
  - putTransaction/getTransaction/getConversation
  - putBlock/getBlockById/getBlockByHeight/tipHeight

6) P2P & Sync (high level)
- WebRtcAdapter: createOfferPayload, acceptOfferAndCreateAnswer, acceptAnswer
- SyncEngine: onBlockAdded(), onTxReceived(); announceTx/announceBlock used internally by PeopleChainNode

Usage Snippets

// Startup
final node = PeopleChainNode();
await node.startNode(const NodeConfig(alias: 'Alice'));
final info = await node.getNodeInfo();
print('NodeId: ${info.nodeId}');

// Send a text message
final result = await node.sendMessage(toPubKey: bobEd25519, text: 'Hello Bob');
if (!result.ok) {
  print('Send failed: ${result.error}');
}

// Read conversation
final msgs = await node.getMessages(withPubKey: bobEd25519, limit: 50);

// WebRTC manual/QR pairing
final offerB64 = await node.createOfferPayload();
// Share offerB64 out-of-band (QR / copy-paste)
final answerB64 = await otherNode.acceptOfferAndCreateAnswer(offerB64);
await node.acceptAnswer(answerB64);

Notes
- All persistence is on-device. No remote servers are required.
- Optional Firebase/Supabase integrations are disabled by default. To enable them in Dreamflow, use the Firebase or Supabase panel and complete setup first.
- On Web, a postMessage API can be toggled from the Testing Dashboard > API tab for external integrations.
