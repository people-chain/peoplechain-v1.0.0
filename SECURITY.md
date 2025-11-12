PeopleChain Security Considerations

Scope
PeopleChain is a fully on-device, decentralized chat ledger. This document describes the cryptographic primitives, secure storage model, threat model, and hardening recommendations.

Cryptography
- Identity and Signing: Ed25519
  - Deterministic keys derived from a 32-byte master seed
  - Used to sign transactions/blocks

- Key Agreement: X25519
  - Used to derive shared secrets (e.g., for session or content encryption contexts)

- Content Encryption: AES-GCM-256
  - Per-chunk encryption; 96-bit nonce; integrity via GHASH
  - Keys derived using HKDF(HMAC-SHA256) with per-context salt and AAD

- Hashing: SHA-256 for content IDs and merkle roots

Secure Storage
- Master seed stored via platform-secure storage APIs
  - Android: EncryptedSharedPreferences
  - iOS: Keychain/Secure Enclave pathways as available
- Backups use Shamir secret sharing with PCS1-encoded shards

Threat Model
- In-scope
  1) Device loss/theft: seed confidentiality at rest
  2) Local DB tampering: detection via signatures/content IDs/merkle roots
  3) Message integrity: signature validation and chunk AAD/nonce handling
  4) Untrusted peers: sync protocol validates before accept/commit
  5) Replay: tx/block IDs and merkle linkage prevent silent duplication

- Out-of-scope
  1) Global network adversary deanonymization (metadata leakage)
  2) Long-term post-compromise confidentiality if seed is exfiltrated
  3) Side-channel attacks on mobile hardware

Hardening Recommendations
1) Strong device unlock (PIN/biometric) and OS updates
2) Optionally gate seed restore with local auth prompt
3) Encourage shard separation; never co-locate all shards
4) Periodic re-key: derive a new seed and rotate identity (app feature)
5) Validate QR/manual signaling contents offline before applying
6) Consider app sandbox jailbreak/root detection to warn users

Privacy Notes
- PeopleChain is peer-to-peer; IP-level metadata and timing are visible to network observers.
- Use LAN (mDNS) when possible to minimize exposure outside local network.

Incident Response
- If a seed compromise is suspected:
  1) Stop node on affected device
  2) Rotate to a new seed (new identity)
  3) Notify peers out-of-band to distrust the old identity
