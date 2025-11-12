PeopleChain API Reference

Overview
PeopleChain is an on-device, fully offline-capable blockchain-style ledger for decentralized chat. It provides:
- Key management (deterministic Ed25519/X25519 from a master seed)
- On-device storage (Isar) for chunks, transactions, blocks, and conversations
- Chunking and encryption (AES-GCM-256 with HKDF)
- P2P transports (WebRTC data channel, mDNS discovery)
- Sync protocol and engine (delta sync, validation, light fork handling)
- Public SDK facade (PeopleChainNode) for app integration

Primary Packages and Namespaces
- lib/peoplechain_core/peoplechain_core.dart (barrel export)
- lib/peoplechain_core/src/* (internal modules)

Key Public Types

1) PeopleChainNode (lib/peoplechain_core/src/sdk/node.dart)
- Lifecycle
  - Future<void> startNode()
  - Future<void> stopNode()
  - bool get isRunning
  - String get nodeId (hex or base58 identifier derived from public key)

- Messaging & Media
  - Future<String> sendMessage({required String conversationId, required String text})
  - Future<String> sendMedia({required String conversationId, required List<int> bytes, String? mimeType})
  - Stream<TxSummary> onTxReceived()
  - Stream<BlockHeader> onBlockAdded()
  - Future<List<TxSummary>> getMessages({required String conversationId, int limit = 50, String? beforeTxId})
  - Future<TxEntity?> getTransactionById(String txId)
  - Future<ChunkEntity?> getChunk(String chunkId)

- Backup & Restore
  - Future<List<String>> backupToShards({required int threshold, required int shares})
  - Future<void> restoreFromShards(List<String> shards)

- P2P / WebRTC Helpers
  - Future<String> createOfferQrPayload()
  - Future<void> acceptAnswerQrPayload(String payload)
  - Future<void> acceptOfferQrPayload(String payload)
  - Future<String> createAnswerQrPayload()

Events
- onTxReceived(): Stream<TxSummary>
- onBlockAdded(): Stream<BlockHeader>

Data Models
- TxSummary
  - String txId
  - String conversationId
  - String senderId
  - int timestampMs
  - bool isMedia
  - String? previewText

- BlockHeader
  - String blockId
  - int height
  - String prevId
  - String merkleRoot
  - int timestampMs

2) CryptoManager (lib/peoplechain_core/src/crypto_manager.dart)
- Deterministic key derivation from a 32-byte master seed
  - Future<Keypair> getEd25519()
  - Future<Keypair> getX25519()
  - Future<List<int>> sign(List<int> message)
  - Future<bool> verify(List<int> message, List<int> signature, List<int> publicKey)
  - Future<List<int>> deriveSharedSecret(List<int> remoteX25519PublicKey)

3) KeyStorage (lib/peoplechain_core/src/key_storage.dart)
- Platform-secure storage of the 32-byte master seed
  - Future<void> saveSeed(List<int> seed)
  - Future<List<int>?> loadSeed()
  - Future<void> deleteSeed()
  - Future<List<String>> backupToShards({required int threshold, required int shares})
  - Future<void> restoreFromShards(List<String> shards)

4) MessageDb Interface (lib/peoplechain_core/src/db/message_db.dart)
- Core persistence interface
  - Future<void> putChunk(ChunkEntity chunk)
  - Future<void> putTransaction(TxEntity tx)
  - Future<void> putBlock(BlockEntity block)
  - Future<ChunkEntity?> getChunk(String id)
  - Future<TxEntity?> getTransaction(String id)
  - Future<BlockEntity?> getBlock(String id)
  - Future<List<TxEntity>> getConversationTx(String conversationId, {int limit = 50, String? beforeTxId})
  - Future<void> close()

5) IsarMessageDb (lib/peoplechain_core/src/db/isar_message_db.dart)
- Isar-backed implementation with checked-in schemas for web and devices
- Adds indices for conversation queries and stable ordering

6) TxBuilder (lib/peoplechain_core/src/tx/tx_builder.dart)
- Build signed transactions (text/media), attach manifests, compute IDs
  - Future<TxEntity> buildTextTx(String conversationId, String text)
  - Future<List<ChunkEntity>> buildMediaChunks(List<int> bytes, {String? mimeType})
  - Future<TxEntity> buildMediaTx(String conversationId, List<ChunkEntity> chunks, {String? mimeType})

7) ChunkCodec (lib/peoplechain_core/src/tx/chunk_codec.dart)
- AES-GCM-256 encrypted chunk format (PCEC v1) with HKDF
  - Future<EncodedChunk> encryptChunk(Uint8List plaintext, {required Uint8List salt, required Uint8List aad})
  - Future<Uint8List> decryptChunk(EncodedChunk chunk, {required Uint8List salt, required Uint8List aad})

8) P2P & Sync
- P2P Manager (lib/peoplechain_core/src/p2p/p2p_manager.dart)
  - Start/stop adapters, track PeerStore, expose events
- WebRtcAdapter (lib/peoplechain_core/src/p2p/adapters/webrtc_adapter.dart)
  - DataChannel transport and QR/manual signaling helpers
- mDNS Adapter (lib/peoplechain_core/src/p2p/adapters/mdns_adapter.dart)
  - LAN discovery of peers (listen + resolve)
- SyncEngine (lib/peoplechain_core/src/sync/sync_engine.dart)
  - Handshake, delta exchange, validation, merge
  - Events: onTxReceived, onBlockAdded

Error Handling
- Most APIs throw FlutterError or ArgumentError for misuse
- Crypto errors surface as StateError
- WebRTC signaling parsing throws FormatException on invalid payloads

Performance Notes
- Batched DB writes where applicable
- Stable ordering via timestamp-padded txId
- Streams are broadcast; remember to cancel subscriptions

Compatibility
- Flutter/Dart 3+, Web, Android, iOS
- No backend required; optional Firebase/Supabase are disabled by default
