Integration Guide — Using PeopleChain in External Apps/Services

1. Flutter SDK integration (recommended)
- Add the SDK source (this repository embeds peoplechain_core) and import:
  import 'package:peoplechain_core/peoplechain_core.dart';

Quick start
  final node = PeopleChainNode();
  await node.startNodeWithProgress(const NodeConfig(alias: 'MyApp'));
  final info = await node.getNodeInfo();
  // Pair via createOfferPayload/acceptOfferAndCreateAnswer/acceptAnswer
  final res = await node.sendMessage(toPubKey: peerEd25519, text: 'Hello');

Common queries
- getMessages(withPubKey, limit)
- getTransactionById(txId)
- getBlockByHeight(height), getBlockById(blockId)
- tipHeight()

2. Web external API (postMessage bridge)
- On Web, you can expose the node via a JS bridge and control it from the browser console or another window/tab.

Enable in Testing Dashboard
- Open the API tab and toggle the switch to expose the API. Use the self‑test form to post a request to the app.

Message format
  const req = { target: 'peoplechain', id: '1', method: 'getInfo', params: {} };
  window.postMessage(req, '*');
  window.addEventListener('message', (e) => {
    if (e.data && e.data.target === 'peoplechain' && e.data.id === '1') {
      console.log('Response', e.data);
    }
  });

Supported methods (subset)
- getInfo, recentPeers {limit}
- createOffer, acceptOffer {offer}, acceptAnswer {answer}
- sendText {toEd25519, text}
- getTx {txId}, getMessages {withPubKey, limit}
- tipHeight, getBlockByHeight {height}, getBlockById {blockId}

3. Data model and integrity
- Transactions are Ed25519‑signed; txId is SHA‑256 over body||signature (base64url).
- Blocks contain a merkle root of txIds; receivers recompute and verify before accepting.

4. Security and operational guidance
- Always surface and verify public key fingerprints when onboarding peers.
- Consider rotating x25519 session keys per connection in future versions for PFS.
- Keep the device secure; the master seed resides in platform secure storage.

5. Extending consensus rules
- Provide a ConsensusHook to SyncEngine to enforce custom validation (e.g., application‑specific invariants). Blocks failing validation are ignored.


6. Discovery Relay (Auto-Discovery via HTTP signaling)

Overview
- PeopleChain can automatically discover peers using a lightweight Discovery Relay (nodescript/discovery_server.js). This relay only forwards opaque base64 SDP blobs and does not store user content. End-to-end encryption is preserved over WebRTC.

Running the relay
- Linux: node nodescript/discovery_server.js
- Windows (PowerShell): node .\nodescript\discovery_server.js
- Configure via environment vars:
  - PEOPLECHAIN_DISCOVERY_HOST (default 0.0.0.0 for server, 127.0.0.1 for clients)
  - PEOPLECHAIN_DISCOVERY_PORT (default 8081)
  - PEOPLECHAIN_DISCOVERY_ALLOW_ORIGINS (default *)

Client behavior
- On startup, clients look for the relay using --dart-define values (PEOPLECHAIN_DISCOVERY_HOST, PEOPLECHAIN_DISCOVERY_PORT) or defaults.
- If reachable, the client announces with POST /announce { nodeId, alias? } and begins long-polling GET /poll?node=... for messages.
- WebRTC signaling proceeds automatically:
  1) Caller creates a base64 offer payload and POSTs /send { from, to, type: 'offer', data }.
  2) Callee receives the offer via /poll, applies it, creates an answer, and POSTs /send { type: 'answer' }.
  3) Caller receives answer via /poll and finishes the handshake. No manual UI steps required.
- If the relay is unavailable, the SDK falls back to LAN discovery (mDNS/Wi‑Fi Direct/BLE) and manual QR/clipboard flows.

How to enable
- Nothing extra is required in app code. Build with optional defines:
  flutter run -d linux --dart-define=PEOPLECHAIN_DISCOVERY_HOST=127.0.0.1 --dart-define=PEOPLECHAIN_DISCOVERY_PORT=8081
- Or simply rely on defaults if the relay runs on the same machine.

Security notes
- Signaling blobs only contain SDP + public identifiers and are base64 wrapped. No plaintext user data is sent to the relay. All content is exchanged over the encrypted WebRTC channel.
