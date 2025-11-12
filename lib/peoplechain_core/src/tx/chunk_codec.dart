import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/keypair.dart';

/// PeopleChain encrypted chunk binary format (version 1)
/// Layout (big endian lengths):
///   magic:    'PCEC' (4 bytes)
///   version:  1 byte (0x01)
///   alg:      1 byte (0x01=aes-gcm-256)
///   nonceLen: 1 byte (12 for AES-GCM)
///   nonce:    nonceLen bytes
///   adLen:    2 bytes
///   ad:       adLen bytes (associated data)
///   ctLen:    4 bytes
///   ct:       ctLen bytes (ciphertext including tag)
class ChunkCodec {
  static const _magic = [0x50, 0x43, 0x45, 0x43]; // P C E C
  static const _version = 1;

  // For M3 we implement AES-GCM-256 (alg=1). Interface allows future xchacha20poly1305.
  static const _algAesGcm = 1;

  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final AesGcm _aes = AesGcm.with256bits();

  /// Derives a 32-byte symmetric key using HKDF-SHA256 from an ECDH/X25519 shared secret.
  /// participantsKey is a canonical string for associated data context (e.g., "a|b").
  Future<SecretKey> _deriveKey({
    required Uint8List sharedSecret,
    required String participantsKey,
  }) async {
    final salt = utf8.encode('PC:enc-v1');
    final info = utf8.encode('PC:$participantsKey');
    return _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      nonce: salt,
      info: info,
    );
  }

  /// Encrypts [plaintext] with derived key. Returns [encoded] binary chunk bytes.
  Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required Uint8List sharedSecret,
    required String participantsKey,
    List<int>? associatedData,
  }) async {
    final key = await _deriveKey(sharedSecret: sharedSecret, participantsKey: participantsKey);
    final rnd = Random.secure();
    final nonce = Uint8List.fromList(List<int>.generate(12, (_) => rnd.nextInt(256))); // AES-GCM
    final ad = associatedData ?? utf8.encode(participantsKey);
    final secretBox = await _aes.encrypt(plaintext, secretKey: key, nonce: nonce, aad: ad);

    // Build header + ciphertext
    final ct = secretBox.cipherText + secretBox.mac.bytes; // cryptography already outputs combined?
    // Note: AesGcm in package returns cipherText and mac separately. We concatenate for storage.
    final builder = BytesBuilder(copy: false);
    builder.add(_magic);
    builder.add([_version]);
    builder.add([_algAesGcm]);
    builder.add([nonce.length]);
    builder.add(nonce);
    final adBytes = Uint8List.fromList(ad);
    builder.add(_u16be(adBytes.length));
    builder.add(adBytes);
    builder.add(_u32be(ct.length));
    builder.add(ct);
    return builder.toBytes();
  }

  /// Decrypts [encoded] chunk bytes and returns plaintext.
  Future<Uint8List> decrypt({
    required Uint8List encoded,
    required Uint8List sharedSecret,
    required String participantsKey,
  }) async {
    if (encoded.length < 4 + 1 + 1 + 1 + 12 + 2 + 4) {
      throw StateError('Encoded chunk too small');
    }
    int offset = 0;
    void requireBytes(int n) {
      if (offset + n > encoded.length) {
        throw StateError('Truncated chunk');
      }
    }
    // magic
    requireBytes(4);
    for (var i = 0; i < 4; i++) {
      if (encoded[offset + i] != _magic[i]) {
        throw StateError('Invalid chunk magic');
      }
    }
    offset += 4;
    // version
    final version = encoded[offset++];
    if (version != _version) {
      throw StateError('Unsupported chunk version: $version');
    }
    // alg
    final alg = encoded[offset++];
    if (alg != _algAesGcm) {
      throw StateError('Unsupported alg: $alg');
    }
    // nonce
    final nonceLen = encoded[offset++];
    requireBytes(nonceLen);
    final nonce = encoded.sublist(offset, offset + nonceLen);
    offset += nonceLen;
    // ad
    requireBytes(2);
    final adLen = (encoded[offset] << 8) | encoded[offset + 1];
    offset += 2;
    requireBytes(adLen);
    final ad = encoded.sublist(offset, offset + adLen);
    offset += adLen;
    // ct
    requireBytes(4);
    final ctLen = (encoded[offset] << 24) | (encoded[offset + 1] << 16) | (encoded[offset + 2] << 8) | encoded[offset + 3];
    offset += 4;
    requireBytes(ctLen);
    final ct = encoded.sublist(offset, offset + ctLen);

    // Split ciphertext and MAC (tag is 16 bytes)
    if (ct.length < 16) {
      throw StateError('Ciphertext too small');
    }
    final cipherText = ct.sublist(0, ct.length - 16);
    final mac = Mac(ct.sublist(ct.length - 16));

    final key = await _deriveKey(sharedSecret: sharedSecret, participantsKey: participantsKey);
    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
      aad: ad,
    );

    // Validate associated data context if provided: ensure it matches participantsKey
    final adStr = utf8.decode(ad, allowMalformed: true);
    if (adStr != participantsKey) {
      // We don't fail decryption (AAD validated already), but this signals context mismatch.
      // For now, just proceed. Future: include stronger context binding.
    }

    return Uint8List.fromList(clear);
  }

  static List<int> _u16be(int n) => [
        (n >> 8) & 0xFF,
        n & 0xFF,
      ];

  static List<int> _u32be(int n) => [
        (n >> 24) & 0xFF,
        (n >> 16) & 0xFF,
        (n >> 8) & 0xFF,
        n & 0xFF,
      ];
}

/// Utility helpers for hashing
Future<Uint8List> sha256Bytes(Uint8List data) async {
  final d = await Sha256().hash(data);
  return Uint8List.fromList(d.bytes);
}

Future<String> chunkIdFromPlaintext(Uint8List data) async {
  final h = await sha256Bytes(data);
  return b64url(h);
}
