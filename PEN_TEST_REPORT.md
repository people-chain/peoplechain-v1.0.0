PeopleChain Internal Pen-Test Report (M8)

Scope
- Platforms: Web, Android, iOS (Flutter/Dart 3+)
- Modules: KeyStorage, CryptoManager, ChunkCodec, TxBuilder, MessageDb (Isar), P2P (WebRTC/mDNS), SyncEngine
- Exclusions: Any external backend (none connected), OS/hardware-level mitigations

Methodology
1) Static review of cryptographic usage and error handling
2) Unit/integration tests covering validation, replays, and tampering
3) Fuzzing of chunk decoder (lengths, nonces, tags)
4) Negative tests for QR/manual signaling parsing (malformed/oversized inputs)
5) Transport-level ordering/reliability checks on WebRTC data channels

Findings
F1. Chunk tampering detection (Passed)
- Tampered ciphertext/nonce/tag fails GCM auth and is rejected.
Severity: — | Status: Mitigated by AES-GCM

F2. Replay handling in sync (Passed)
- Replayed tx/block IDs are recognized; duplicates are ignored.
Severity: — | Status: Mitigated by IDs/merkle linkage

F3. Signature verification coverage (Passed)
- All incoming txs/blocks validated before commit.
Severity: — | Status: Mitigated by Ed25519 verification

F4. Signaling payload validation (Informational)
- Malformed base64/JSON raises FormatException; size checks applied.
Severity: Low | Recommendation: keep conservative size limits

F5. DoS via large media (Informational)
- Very large media increases chunk count; storage/memory pressure possible.
Severity: Low | Recommendation: enforce max media size per app policy

F6. Metadata exposure (Known limitation)
- P2P reveals network metadata (IP/timing). No built-in obfuscation.
Severity: Medium | Recommendation: document privacy tradeoffs; consider future relay/TURN policy prompts

F7. Seed exfiltration on rooted devices (Known limitation)
- If device is compromised, local secure storage may be bypassed.
Severity: Medium | Recommendation: warn users; offer optional local auth gate on critical actions

Recommendations Summary
- Enforce app-level media size caps
- Add optional local auth prompt on restore/backup
- Provide clear privacy documentation around P2P metadata
- Keep dependencies patched (webrtc, isar)

Attestation
- Tests and reviews executed for M8 timeline. All critical controls behaved as designed.
