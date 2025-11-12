import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

class Share {
  final int index; // 1..255
  final Uint8List data; // same length as secret

  Share(this.index, this.data) {
    if (index < 1 || index > 255) {
      throw ArgumentError('Share index must be in 1..255');
    }
  }
}

class Shamir {
  static const int _fieldPoly = 0x11b; // GF(256) irreducible polynomial
  static final Uint8List _exp = _buildExpTable();
  static final Uint8List _log = _buildLogTable(_exp);

  static Uint8List _buildExpTable() {
    final exp = Uint8List(512);
    int x = 1;
    for (int i = 0; i < 255; i++) {
      exp[i] = x;
      x <<= 1;
      if (x & 0x100 != 0) {
        x ^= _fieldPoly;
      }
    }
    for (int i = 255; i < 512; i++) {
      exp[i] = exp[i - 255];
    }
    return exp;
  }

  static Uint8List _buildLogTable(Uint8List exp) {
    final log = Uint8List(256);
    for (int i = 0; i < 255; i++) {
      log[exp[i]] = i;
    }
    log[0] = 0; // undefined, but set to 0 to avoid crashes; handle in mul
    return log;
  }

  static int _gfAdd(int a, int b) => a ^ b;

  static int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    final res = _exp[_log[a] + _log[b]];
    return res;
  }

  static int _gfDiv(int a, int b) {
    if (b == 0) throw ArgumentError('Division by zero in GF(256)');
    if (a == 0) return 0;
    int idx = _log[a] - _log[b];
    if (idx < 0) idx += 255;
    return _exp[idx];
  }

  static Share _makeShare(
    int index,
    Uint8List secret,
    int threshold,
    Random random,
  ) {
    final out = Uint8List(secret.length);
    for (int byteIdx = 0; byteIdx < secret.length; byteIdx++) {
      final s = secret[byteIdx];
      // Random coefficients for polynomial f(x) = s + a1*x + a2*x^2 + ...
      final coeffs = Uint8List(threshold);
      coeffs[0] = s;
      for (int j = 1; j < threshold; j++) {
        coeffs[j] = random.nextInt(256);
      }

      int x = index;
      int y = 0;
      int xPow = 1; // x^0
      for (int j = 0; j < threshold; j++) {
        // y += coeffs[j] * x^j
        final term = _gfMul(coeffs[j], xPow);
        y = _gfAdd(y, term);
        xPow = _gfMul(xPow, x);
      }
      out[byteIdx] = y;
    }
    return Share(index, out);
  }

  static List<Share> split(Uint8List secret, int threshold, int shares) {
    if (threshold < 2) {
      throw ArgumentError('Threshold must be >= 2');
    }
    if (shares < threshold) {
      throw ArgumentError('Shares must be >= threshold');
    }
    if (shares > 255) {
      throw ArgumentError('Shares must be <= 255');
    }
    final rnd = Random.secure();
    return List.generate(
      shares,
      (i) => _makeShare(i + 1, secret, threshold, rnd),
      growable: false,
    );
  }

  static Uint8List combine(List<Share> shares) {
    if (shares.isEmpty) {
      throw ArgumentError('At least one share required');
    }
    final length = shares.first.data.length;
    for (final s in shares) {
      if (s.data.length != length) {
        throw ArgumentError('Shares have different lengths');
      }
    }

    final k = shares.length;
    final secret = Uint8List(length);
    for (int byteIdx = 0; byteIdx < length; byteIdx++) {
      int acc = 0;
      for (int i = 0; i < k; i++) {
        final xi = shares[i].index;
        final yi = shares[i].data[byteIdx];

        // Lagrange basis polynomial L_i(0)
        int li = 1;
        for (int j = 0; j < k; j++) {
          if (i == j) continue;
          final xj = shares[j].index;
          final num = _gfAdd(0, xj); // (0 - xj) == xj in GF(256) since subtraction==addition
          final den = _gfAdd(xi, xj);
          li = _gfMul(li, _gfDiv(num, den));
        }
        acc = _gfAdd(acc, _gfMul(yi, li));
      }
      secret[byteIdx] = acc;
    }
    return secret;
  }

  // Encoding helpers (versioned simple format)
  // Format: "PCS1|<index>|<b64url(data)>"
  static String encodeShare(Share share) {
    final b64 = base64Url.encode(share.data).replaceAll('=', '');
    return 'PCS1|${share.index}|$b64';
  }

  static Share decodeShare(String text) {
    final parts = text.split('|');
    if (parts.length != 3 || parts[0] != 'PCS1') {
      throw FormatException('Invalid share format');
    }
    final idx = int.parse(parts[1]);
    var b64 = parts[2];
    while (b64.length % 4 != 0) {
      b64 += '=';
    }
    final data = Uint8List.fromList(base64Url.decode(b64));
    return Share(idx, data);
  }
}
