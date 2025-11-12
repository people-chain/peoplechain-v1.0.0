import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:pocket_coach/peoplechain_core/src/utils/shamir.dart';

void main() {
  group('Shamir Secret Sharing', () {
    test('split and combine works with threshold 3 of 5', () {
      final rnd = Random(42);
      final secret = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
      final shares = Shamir.split(secret, 3, 5);
      expect(shares.length, 5);

      final recovered1 = Shamir.combine([shares[0], shares[1], shares[2]]);
      expect(recovered1, secret);

      final recovered2 = Shamir.combine([shares[4], shares[1], shares[3]]);
      expect(recovered2, secret);
    });

    test('encode/decode preserves share', () {
      final secret = Uint8List.fromList(List.generate(16, (i) => i));
      final share = Shamir.split(secret, 2, 3).first;
      final enc = Shamir.encodeShare(share);
      final dec = Shamir.decodeShare(enc);
      expect(dec.index, share.index);
      expect(dec.data, share.data);
    });
  });
}
