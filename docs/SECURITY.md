PeopleChain Security Considerations

Scope and goals
- Fully on-device decentralized chat ledger with P2P replication (no servers required)
- Protect message integrity and metadata consistency; protect media confidentiality at rest and in transit
- Provide safe key lifecycle and backup mechanisms

Key material and storage
- Master seed: 32 bytes, randomly generated (Random.secure)
- Key derivations:
  - Ed25519 keypair = Ed25519.newKeyPairFromSeed(masterSeed)
  - X25519 keypair = X25519.newKeyPairFromSeed(SHA-256("PC:x25519" || masterSeed))
- Storage: platform secure storage via flutter_secure_storage
  - Android: EncryptedSharedPreferences
  - iOS: Keychain (Secure Enclave backed where available by Apple)
- Public descriptor (CombinedKeyPairDescriptor) stored alongside to avoid exposing private material

Message signing and IDs
- Text and media transactions are represented as canonical JSON (deterministic field ordering) and signed with Ed25519
- txId = base64url(SHA-256(body || signature)) to prevent malleability and provide stable IDs

Media encryption (ChunkCodec PCEC v1)
- Per-chunk AEAD: AES-GCM-256
- Symmetric key derived by HKDF(HMAC-SHA256) from X25519 shared secret:
  - salt = "PC:enc-v1"
  - info = "PC:" + participantsKey (canonical "a|b" by x25519 public keys)
- Nonce: 12 random bytes (Random.secure)
- AAD: participantsKey (binds context to the communicating pair)
- Stored binary format includes magic, version, algorithm id, nonce, ad length/data and ciphertext||tag

Transport security
- WebRTC DataChannel provides DTLS and SRTP, but identity verification is out-of-band in manual/QR mode
- Recommendation: verify peer identity by comparing known public keys (ed25519/x25519) conveyed in QR payloads; optionally display a short authentication string to users

Discovery
- mDNS browsing (no advertising by default). Metadata parsed from TXT records if present. Avoids exposing sensitive data; only public keys and alias may be visible.

Backup & recovery
- Shamir Secret Sharing (GF(256)) over the master seed
- Encoded as PCS1: "PCS1|index|base64url(data)"
- Any threshold subset reconstructs the seed; keep shards offline and separated

Threat model (high level)
- Covered
  - At-rest seed protection via platform secure storage
  - Integrity of transactions via Ed25519 signatures
  - Confidentiality of media chunks via AES-GCM-256 with per-chunk random nonces
  - Replay resistance in sync by message IDs and request semantics
- Not covered / limitations
  - No Perfect Forward Secrecy: X25519 uses static keys derived from the seed; compromise of long-term keys can decrypt past media chunks if the shared secret can be recomputed
  - Manual/QR pairing lacks in-band identity verification; a malicious relay could attempt MITM if users don’t verify fingerprints
  - mDNS traffic is observable on the local LAN

Operational recommendations
- Display peer key fingerprints during pairing; require user confirmation
- Optionally rotate x25519 session keys in future versions for PFS
- Keep dependencies up to date; audit cryptography and WebRTC packages
- Consider encrypting Isar database at rest if device-level encryption is insufficient
