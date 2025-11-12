# PeopleChain Core SDK — API Reference

This reference covers public classes, functions, and streams exposed by `peoplechain_core` (lib/peoplechain_core/peoplechain_core.dart).

Note: Types below refer to Dart classes in the SDK. See code snippets for usage.

## PeopleChainNode

Description: Facade for running a local node, managing discovery, sync, messaging, and chain queries.

- startNode(config: NodeConfig): Future<void>
  - Starts the node without progress updates.
  - Params: config (NodeConfig)
  - Returns: Future<void>
  - Example:
    ```dart
    final node = PeopleChainNode();
    await node.startNode(const NodeConfig(alias: 'Alice'));
    ```

- startNodeWithProgress(config: NodeConfig): Future<void>
  - Starts the node and emits step-wise progress on onInitProgress().
  - Example:
    ```dart
    final sub = node.onInitProgress().listen((u) => print('${u.id}: ${u.status}'));
    await node.startNodeWithProgress(const NodeConfig(alias: 'Alice'));
    ```

- enableAutoMode(): Future<void>
  - Enables automatic discovery/bootstrap. On Web, starts broadcast-based WebRTC auto-exchange.
  - Returns: Future<void>

- stopNode(): Future<void>
  - Stops sync, discovery, and closes DB.

- onBlockAdded(): Stream<BlockEvent>
  - Emits when a block is added locally.

- onTxReceived(): Stream<TxEvent>
  - Emits when a transaction is received by this node.

- onPeerDiscovered(): Stream<PeerInfo>
  - Emits peers discovered via mDNS/Nearby/WebRTC payloads.

- onSyncState(): Stream<SyncState>
  - Emits SyncState.connecting → handshaking → synced.

- getNodeInfo(): Future<NodeInfo>
  - Returns node id, keys, alias, and tip height.

- sendMessage({toPubKey, text}): Future<TxResult>
  - Sends a text message. Encrypts automatically if recipient X25519 is known.
  - Params: toPubKey (ed25519 in base64url), text (String)
  - Returns: TxResult
  - Example:
    ```dart
    final res = await node.sendMessage(toPubKey: bobEd25519, text: 'Hello');
    ```

- sendMedia({toPubKey, bytes, mime}): Future<TxResult>
  - Sends encrypted media using chunk storage.

- getMessages({withPubKey, limit}): Future<List<TxModel>>
  - Returns a conversation with a peer given their ed25519 key.

- resolveText(tx: TxModel): Future<String?>
  - Resolves plaintext for text transactions, decrypting if necessary.

- tipHeight(): Future<int>
- getTransactionById(id): Future<TxModel?>
- getBlockById(id): Future<BlockModel?>
- getBlockByHeight(h): Future<BlockModel?>

## NodeConfig
- alias: String? — Optional display alias
- useIsarDb: bool — Defaults to true (in-memory used on Web elsewhere)

## NodeInfo
- nodeId: String — Stable key id derived from seed
- keys: PublicIdentity — ed25519 and x25519 base64url strings
- alias: String?
- tipHeight: int

## Streams and Events
- BlockEvent { block: BlockModel }
- TxEvent { tx: TxModel }
- SyncState: connecting | handshaking | synced

## Crypto and Backup
- CryptoManager
  - hasKeys(): Future<bool>
  - generateAndStoreKeys(): Future<void>
  - getDescriptor(): Future<CombinedKeyPairDescriptor?>

- KeyStorage (via CryptoManager.storage)
  - backupToShards({shares, threshold}): Future<List<String>>
  - restoreFromShards(List<String>): Future<void>

### Example: Backup and Restore
```dart
final crypto = CryptoManager();
if (!await crypto.hasKeys()) {
  await crypto.generateAndStoreKeys();
}
final shards = await crypto.storage.backupToShards(shares: 5, threshold: 3);
// Store shards securely offline.
// To restore later:
await crypto.storage.restoreFromShards(shards.take(3).toList());
```

## P2P and Discovery
- P2PManager (created internally by PeopleChainNode)
  - Start/stop discovery over mDNS, Nearby (Android), and WebRTC payload paths.
  - onPeerDiscovered(): Stream<PeerInfo>

## REST and WebSocket (Monitor Server)
When the embedded monitor server is enabled (Linux/desktop), the node exposes:
- WebSocket: ws://127.0.0.1:8080/ws
- REST: http://127.0.0.1:8080/api/*
  - GET /api/info
  - GET /api/tip
  - GET /api/peers?limit=100
  - GET /api/blocks?from=tip&count=20
  - GET /api/block/{id}
  - GET /api/tx/{id}
