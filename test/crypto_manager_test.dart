import 'dart:typed_data';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:pocket_coach/peoplechain_core/src/crypto_manager.dart';
import 'package:pocket_coach/peoplechain_core/src/key_storage.dart';

void main() {
  group('CryptoManager', () {
    test('generate, sign, and derive shared secret', () async {
      final storageA = KeyStorage(driver: InMemorySecureStorageDriver());
      final cmA = CryptoManager(storage: storageA);
      final descA = await cmA.generateAndStoreKeys();
      expect(descA.publicIdentity.ed25519.isNotEmpty, true);

      final storageB = KeyStorage(driver: InMemorySecureStorageDriver());
      final cmB = CryptoManager(storage: storageB);
      final descB = await cmB.generateAndStoreKeys();

      // Sign
      final msg = Uint8List.fromList([1, 2, 3]);
      final sig = await cmA.sign(msg);
      // Just check non-empty signature
      expect(sig.isNotEmpty, true);

      // Shared secret symmetry
      // Parse B's x25519 public key
      // Decode base64url
      String pad(String s) { while (s.length % 4 != 0) { s += '='; } return s; }
      final bPub = Uint8List.fromList(
        (base64Url.decode(pad(descB.publicIdentity.x25519)))
      );
      final aShared = await cmA.sharedSecret(bPub);

      final aPub = Uint8List.fromList(
        (base64Url.decode(pad(descA.publicIdentity.x25519)))
      );
      final bShared = await cmB.sharedSecret(aPub);
      expect(aShared, bShared);
    });
  });
}
