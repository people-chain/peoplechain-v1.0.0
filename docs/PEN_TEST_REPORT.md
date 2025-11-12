PeopleChain Penetration Test Summary (M8)

Scope
- peoplechain_core SDK (Flutter/Dart)
- Storage: Isar-backed MessageDb + secure storage (flutter_secure_storage)
- Transport: WebRTC data channel (manual/QR pairing), mDNS discovery
- Platforms: Android, iOS, Web

Methodology
- Static analysis and manual code review
- Dependency inspection (licenses, known CVEs)
- Cryptographic usage review (apikeys: none; key generation, signing, encryption)
- Local storage review (seed handling, descriptors, chunk storage)
- Network flow review (WebRTC handshake payloads, message envelopes, replay surface)

Findings
1) Identity verification during pairing (Medium)
   - Description: Manual/QR WebRTC pairing does not authenticate the remote peer by default beyond the out-of-band QR exchange. A malicious relay could facilitate a MITM if users do not compare fingerprints.
   - Impact: Potential interception if an attacker tampers with QR payloads and victims do not verify identities
   - Recommendation: Show ed25519/x25519 fingerprints on both sides and require users to confirm a short authentication string prior to accepting the connection.

2) No perfect forward secrecy for media (Medium)
   - Description: AES-GCM keys derive from static X25519 long-term keys; compromise of the master seed allows recomputation of shared secrets.
   - Impact: Past media chunks may be decrypted post-compromise
   - Recommendation: Introduce ephemeral X25519 per-session key agreement and derive per-session symmetric keys; rotate periodically.

3) mDNS metadata exposure (Low)
   - Description: Public keys and alias can be observed on the local network during discovery.
   - Impact: Limited metadata leakage to LAN observers
   - Recommendation: Allow users to disable LAN discovery; keep TXT records minimal; document behavior.

4) Input validation around JSON envelopes (Low)
   - Description: JSON parsing guards exist; malformed frames are ignored. No crashes observed, but fuzzing could be extended.
   - Impact: Low; DoS by sending many malformed messages theoretically possible
   - Recommendation: Rate-limit control frames and drop peers exceeding thresholds.

5) Isar at-rest encryption (Informational)
   - Description: Isar database is not encrypted by this SDK. Device storage encryption may suffice.
   - Recommendation: Consider at-rest DB encryption for highly sensitive deployments.

Positive Observations
- Ed25519 signatures on transactions; canonical serialization
- AES‑GCM‑256 for media; HKDF(HMAC‑SHA256) key derivation; random nonces per chunk
- Secure seed storage with Shamir backup encoding (PCS1)
- No backend dependencies; reduced remote attack surface

Tests Performed
- Key lifecycle
  - Generated keys and verified descriptor persisted without exposing private material
  - Backup/restore via Shamir shares; verified deterministic re-derivation of keys
- Storage
  - Inserted/queried chunks, transactions, and blocks; validated indices and ordering
- Transport/Sync
  - Simulated peers exchanging handshake, deltas, and tx announces; verified replay handling and merkle checks
  - WebRTC loopback harness (manual) to validate data channel behavior
- Fuzzing (light)
  - Injected malformed JSON frames; verified parser resilience and safe failure

Risk ratings
- High: none observed in current on-device scope
- Medium: pairing identity, forward secrecy
- Low: mDNS metadata, JSON envelope hardening

Remediation roadmap
1) Add peer fingerprint verification in UI workflows (short authentication string)
2) Add ephemeral X25519 session keys and rekeying strategy for PFS
3) Optional DB-at-rest encryption
4) Rate limiting and backpressure on sync messages
