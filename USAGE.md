PeopleChain Usage Guide

Prerequisites
- Flutter/Dart 3+
- No backend required. If you later want cloud backup or remote relay, open the Firebase or Supabase panel in Dreamflow and complete setup there. Do not use CLI tools here.

1) Import the SDK
Import the barrel export and create a node instance.

```dart
import 'package:your_app/peoplechain_core/peoplechain_core.dart';

final node = PeopleChainNode();
```

2) Start the node
Start early in app lifecycle (e.g., after user grants storage permissions if needed on Android). On web, no extra permissions are needed.

```dart
await node.startNode();
print('Node ID: ${node.nodeId}');
```

3) Listen to events

```dart
final txSub = node.onTxReceived().listen((tx) {
  // Update chat UI
});
final blockSub = node.onBlockAdded().listen((b) {
  // Optional: show sync progress or block height
});
```

4) Send a text message

```dart
final txId = await node.sendMessage(
  conversationId: 'alice-bob',
  text: 'Hello from PeopleChain!'
);
```

5) Send media

```dart
// bytes can come from file picker, camera, etc.
final txId = await node.sendMedia(
  conversationId: 'alice-bob',
  bytes: myImageBytes,
  mimeType: 'image/png',
);
```

6) Load conversation history

```dart
final history = await node.getMessages(conversationId: 'alice-bob', limit: 50);
```

7) WebRTC manual/QR handshake
Use this to connect two peers over the internet without servers (manual signaling via QR or copy/paste strings).

- Initiator creates an offer payload and shows it as a QR or text:
```dart
final offerPayload = await node.createOfferQrPayload();
// Display offerPayload to user (QR/text)
```

- Responder scans/pastes the offer, produces an answer, and sends it back:
```dart
await node.acceptOfferQrPayload(offerPayload);
final answerPayload = await node.createAnswerQrPayload();
// Display answerPayload back to initiator
```

- Initiator completes by accepting the answer:
```dart
await node.acceptAnswerQrPayload(answerPayload);
```

8) Backup and restore (Shamir secret sharing)
The master seed is the only secret you need to back up.

```dart
final shards = await node.backupToShards(threshold: 2, shares: 3);
// Store shards separately (e.g., different devices/people)

// To restore on a new install/device
await node.restoreFromShards([shards[0], shards[2]]);
```

9) Shutdown

```dart
await node.stopNode();
txSub.cancel();
blockSub.cancel();
```

Dreamflow tips
- Preview: Use the Preview panel to interact with the app live.
- Inspect Mode: Toggle to select widgets and tweak properties.
- Backend: If you decide to add Firebase or Supabase later, open the respective panel in Dreamflow and follow the integrated setup flow. Avoid CLI-based setup here.

Troubleshooting
- If you see runtime errors, open the Dreamflow Debug Console and share the logs.
- Ensure camera/storage permissions if you wire capture flows on Android/iOS.
