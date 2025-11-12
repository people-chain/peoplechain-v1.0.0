# PeopleChain Core SDK — Integration Guide

This guide shows how to import `peoplechain_core`, start a node, exchange messages, query data, and manage backups across Android, Web, and Linux.

No backend required. For cloud features later, use Dreamflow’s Firebase/Supabase panel to set up.

## 1. Add Dependency (inside your Flutter app)

PeopleChain is already part of this repository. If integrating into another app, include it as a local package or copy `lib/peoplechain_core` into your project and export `peoplechain_core.dart`.

```dart
import 'package:your_app/peoplechain_core/peoplechain_core.dart';
```

## 2. Minimal Startup (Android/Web/Linux)
```dart
final node = PeopleChainNode();
await node.startNodeWithProgress(const NodeConfig(alias: 'Alice'));
await node.enableAutoMode(); // auto-discovery (Web auto-RTC, Android Nearby, mDNS)

// Subscribe to events
node.onTxReceived().listen((e) => print('TX: ${e.tx.txId}'));
node.onBlockAdded().listen((e) => print('BLOCK: ${e.block.header.blockId}'));
```

Android: request runtime permissions (Bluetooth, Nearby Wi‑Fi, notifications). In this repo, `requestDiscoveryPermissionsIfNeeded()` handles it at startup.

## 3. Sending and Receiving Messages
```dart
// Get a peer’s ed25519 pubkey (from discovery or QR/manual exchange)
final bobEd25519 = 'BASE64URL_ED25519';

// Text (auto-encrypts if X25519 is known)
final res = await node.sendMessage(toPubKey: bobEd25519, text: 'Hello, Bob!');
print('Sent: ${res.ok}  txId=${res.txId}');

// Resolve plaintext when reading
node.onTxReceived().listen((e) async {
  final text = await node.resolveText(e.tx);
  print('Got message: $text');
});
```

## 4. Querying Chain State
```dart
final tip = await node.tipHeight();
final latest = await node.getBlockByHeight(tip);
final tx = await node.getTransactionById('TX_ID');
```

## 5. Live Updates via Streams
```dart
node.onSyncState().listen((s) => print('Sync: $s'));
node.onPeerDiscovered().listen((p) => print('Peer: ${p.nodeId} via ${p.transports}'));
```

## 6. Backup and Restore
```dart
final crypto = CryptoManager();
if (!await crypto.hasKeys()) await crypto.generateAndStoreKeys();
final shards = await crypto.storage.backupToShards(shares: 5, threshold: 3);
// Securely store shards offline.

// Restore later (needs any threshold shards)
await crypto.storage.restoreFromShards(shards.take(3).toList());
```

## 7. Bootstrap, Sync, and Prune
- Bootstrap: handled automatically by enableAutoMode() + discovery.
- Sync: starts when WebRTC transport connects; emits blocks/tx.
- Prune: current SDK exposes read-only chain APIs. App-specific pruning can be done by rotating storage or snapshotting. A formal pruning API may be added later.

## 8. REST/WebSocket from External Apps (Linux Node)
Start the node with the monitor server (Linux/desktop): it runs at http://127.0.0.1:8080

Example: GET /api/info
```bash
curl http://127.0.0.1:8080/api/info
```

WebSocket: ws://127.0.0.1:8080/ws (send {"type":"get_info"})

Use /api/EXPLORER.html to interactively explore endpoints in a browser.

## 9. Platform Notes
- Android: Foreground service is started to keep the node active in background. Ensure notification permissions on Android 13+.
- Web: Uses in-memory DB; WebRTC auto-discovery via BroadcastChannel. Tab visibility doesn’t stop sync.
- Linux: Monitor Server auto-starts (127.0.0.1:8080) for metrics, REST, and WS.
