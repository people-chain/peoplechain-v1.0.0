PeopleChain Core SDK — Usage Guide (Updated)

Overview
PeopleChain is a fully on-device, peer-to-peer chat ledger for Flutter/Dart apps. It ships with:
- Deterministic Ed25519/X25519 keypairs from a master seed kept in secure storage
- Isar-backed storage with checked-in schemas (Android) and in-memory mode on Web
- WebRTC data channel transport with manual/QR SDP exchange
- mDNS LAN discovery (mobile/Desktop only)
- AES‑GCM‑256 chunk encryption for media

Adding the SDK to your app
Option A — Local path dependency (monorepo)
- Copy sdk_release/peoplechain_core into your repository
- In your app/pubspec.yaml:
  dependencies:
    peoplechain_core:
      path: ./sdk_release/peoplechain_core

Option B — Publish/consume as a package (advanced)
- Use sdk_release/peoplechain_core as the package root
- Update pubspec.yaml metadata, then publish to your private registry or pub.dev

Import
import 'package:peoplechain_core/peoplechain_core.dart';

Quick start
final node = PeopleChainNode();
await node.startNode(const NodeConfig(alias: 'Alice'));
final info = await node.getNodeInfo();
print('Node started: ${info.nodeId} (ed25519: ${info.keys.ed25519})');

// Subscribe to inbound events
node.onTxReceived().listen((e) => print('New tx: ${e.tx.txId}'));
node.onBlockAdded().listen((e) => print('New block: h=${e.block.header.height}'));

// Manual/QR pairing (WebRTC)
// On Alice
final offerB64 = await node.createOfferPayload();
// Show as QR or copy-paste offerB64 to Bob

// On Bob
final answerB64 = await otherNode.acceptOfferAndCreateAnswer(offerB64);
// Return answerB64 to Alice (QR or copy-paste)

// Back on Alice
await node.acceptAnswer(answerB64);

// Send a text
final res = await node.sendMessage(toPubKey: bobEd25519, text: 'Hello Bob');

// Send media (bytes + MIME)
final res2 = await node.sendMedia(toPubKey: bobEd25519, bytes: imageBytes, mime: 'image/jpeg');

// Query conversation
final history = await node.getMessages(withPubKey: bobEd25519, limit: 100);

Backup & restore keys (Shamir secret sharing)
final shards = await node.backupToShards(total: 5, threshold: 3);
// Store shards securely offline; any 3 can restore the seed
await node.restoreFromShards(shardsSubset);

Platform notes
Android
- Required permissions (AndroidManifest.xml):
  - android.permission.INTERNET
  - android.permission.ACCESS_NETWORK_STATE
  - android.permission.ACCESS_WIFI_STATE
  - android.permission.CHANGE_WIFI_MULTICAST_STATE (for mDNS browsing)

iOS
- Add the following to Info.plist for local network browsing:
  - NSLocalNetworkUsageDescription: "PeopleChain discovers peers on your local network."
  - NSBonjourServices: ["_peoplechain._udp"]
- No camera/microphone permissions are required; WebRTC data channels are used without media tracks.

Web
- Works in modern browsers. No special permissions. Branding and PWA manifest are configured under web/.

Dreamflow note
- This project runs fully on-device. If you later choose to add optional Firebase or Supabase features, open the Firebase (or Supabase) panel in Dreamflow and complete setup there. Do not use CLI-based setup within Dreamflow.
