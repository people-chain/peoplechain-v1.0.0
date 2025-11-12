PeopleChain — Concept, Architecture, Consensus, and Sync

1. Concept and purpose
- PeopleChain is an on-device, peer‑to‑peer ledger designed for decentralized chat and lightweight data exchange. It runs fully on end‑user devices with no required backend. Messages and media are persisted locally and replicated between peers over encrypted transports (WebRTC data channel). The SDK exposes a simple Node API that apps can embed to gain distributed, offline‑first messaging and storage.

Primary goals:
- Zero server dependency for core operation
- Private-by-default storage on device; cryptographic integrity for transactions
- Simple, deterministic conflict resolution for a single linear chain of blocks
- Easy developer ergonomics for Flutter apps

2. System architecture and workflow
Layers
- SDK facade: PeopleChainNode — single surface used by the app
- Crypto & keys: CryptoManager + KeyStorage (ed25519/x25519 from a master seed in secure storage)
- Storage: MessageDb with IsarMessageDb (Isar on Android; in-memory on Web)
- Transactions: TxBuilder (text/media → signed transactions + optional encrypted chunks)
- Transport & discovery: WebRtcAdapter for data channel; P2PManager for discovery and peer tracking
- Sync: SyncEngine (handshake + delta blocks/tx exchange)

Workflow
1) Startup: node opens storage, loads/generates keys, initializes TxBuilder, ensures a genesis block exists (h=0)
2) Transport: the WebRTC adapter is created; P2PManager starts discovery and prepares connections
3) Sync: once a data channel opens, nodes exchange hello/hello_ack with tip height and block id, then stream missing blocks/txs
4) App usage: app composes and submits transactions via the node, which announces them to connected peers; blocks are aggregated and propagated by SyncEngine

Diagrams
- See diagrams/architecture.mmd and diagrams/sync_sequence.mmd for Mermaid sources

3. Election and consensus mechanism
PeopleChain implements a lightweight, single‑chain selection rule suitable for mobile P2P:
- Height preference: higher chain height always wins
- Tie‑break at equal height: lexicographically larger blockId is preferred
- Integrity checks: chain linkage validated (prev hash), and tx merkle root recomputed to match header
- Optional hook: a ConsensusHook can perform custom validation per block (e.g., application rules)

Implications:
- This is not a BFT protocol; it is an eventual‑consistency rule for small peer groups where partitions heal quickly
- Forks at the same height resolve deterministically on contact

4. Node synchronization and data propagation
Handshake and delta
- hello/hello_ack exchange local tip (height + block id)
- If behind, a node requests a contiguous block range via get_blocks; provider responds with blocks
- For each block, the receiver recomputes the merkle root and validates prev linkage; if missing tx, it requests them with get_txs before committing the block

Announcements
- Nodes announce newly created tx via inv_txs; peers fetch missing items
- Nodes announce candidate blocks via inv_blocks; peers request missing ranges

5. Integrating PeopleChain as a distributed database layer
Approaches:
- In‑app SDK: import peoplechain_core and use PeopleChainNode for full control in Flutter apps
- Web external API: on Web, enable the js_bridge to expose a postMessage API for cross‑window or external script integration

Data model:
- TxModel covers text and media/file payloads; media chunks are optionally encrypted with AES‑GCM‑256 derived from x25519 shared secrets
- BlockModel aggregates txIds with a header including merkle root, height, and proposer id

Security notes:
- Manual/QR pairing requires out‑of‑band identity verification (compare key fingerprints)
- Keys are derived from a master seed kept in platform secure storage; support Shamir backup shards for recovery
