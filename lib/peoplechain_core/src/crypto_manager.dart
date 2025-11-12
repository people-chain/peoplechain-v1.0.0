import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'key_storage.dart';
import 'models/keypair.dart';

class CryptoManager {
  final KeyStorage storage;

  CryptoManager({KeyStorage? storage}) : storage = storage ?? KeyStorage();

  Future<Uint8List> _generateMasterSeed() async {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  // Deterministic derivations from master seed
  Future<SimpleKeyPair> _ed25519FromSeed(Uint8List seed) async {
    final ed = Ed25519();
    return await ed.newKeyPairFromSeed(seed);
  }

  Future<SimpleKeyPair> _x25519FromSeed(Uint8List seed) async {
    // Derive x25519 seed = SHA256("PC:x25519" + seed)
    final digest = await Sha256().hash(<int>[...utf8.encode('PC:x25519'), ...seed]);
    final xSeed = Uint8List.fromList(digest.bytes);
    final x = X25519();
    return await x.newKeyPairFromSeed(xSeed);
  }

  Future<CombinedKeyPairDescriptor> generateAndStoreKeys() async {
    final seed = await _generateMasterSeed();
    final ed = await _ed25519FromSeed(seed);
    final xk = await _x25519FromSeed(seed);

    final edPub = await ed.extractPublicKey();
    final xPub = await xk.extractPublicKey();
    final meta = CombinedKeyPairMeta(
      keyId: const Uuid().v4(),
      createdAt: DateTime.now().toUtc(),
    );
    final desc = CombinedKeyPairDescriptor(
      publicIdentity: PublicIdentity(
        ed25519: b64url(Uint8List.fromList(edPub.bytes)),
        x25519: b64url(Uint8List.fromList(xPub.bytes)),
      ),
      meta: meta,
    );

    await storage.saveSeed(seed);
    await storage.saveDescriptor(desc);
    return desc;
  }

  Future<bool> hasKeys() async {
    final s = await storage.loadSeed();
    return s != null;
  }

  Future<CombinedKeyPairDescriptor?> getDescriptor() async {
    return storage.loadDescriptor();
  }

  Future<SimpleKeyPair> _requireEd25519() async {
    final seed = await storage.loadSeed();
    if (seed == null) throw StateError('No seed in storage');
    return _ed25519FromSeed(seed);
  }

  Future<SimpleKeyPair> _requireX25519() async {
    final seed = await storage.loadSeed();
    if (seed == null) throw StateError('No seed in storage');
    return _x25519FromSeed(seed);
  }

  Future<Uint8List> sign(Uint8List message) async {
    final ed = await _requireEd25519();
    final edAlgo = Ed25519();
    final sig = await edAlgo.sign(message, keyPair: ed);
    return Uint8List.fromList(sig.bytes);
  }

  Future<bool> verify({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    final ed = Ed25519();
    return await ed.verify(
      message,
      signature: Signature(signature, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
  }

  Future<Uint8List> sharedSecret(Uint8List remoteX25519PublicKey) async {
    final xAlgo = X25519();
    final local = await _requireX25519();
    final shared = await xAlgo.sharedSecretKey(
      keyPair: local,
      remotePublicKey: SimplePublicKey(remoteX25519PublicKey, type: KeyPairType.x25519),
    );
    final bytes = await shared.extractBytes();
    return Uint8List.fromList(bytes);
  }
}
