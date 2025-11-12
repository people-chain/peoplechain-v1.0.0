import 'dart:convert';
import 'dart:typed_data';

class PublicIdentity {
  final String ed25519; // base64url (no padding)
  final String x25519; // base64url (no padding)

  const PublicIdentity({required this.ed25519, required this.x25519});

  Map<String, dynamic> toJson() => {
        'ed25519': ed25519,
        'x25519': x25519,
      };

  factory PublicIdentity.fromJson(Map<String, dynamic> json) => PublicIdentity(
        ed25519: json['ed25519'] as String,
        x25519: json['x25519'] as String,
      );
}

class CombinedKeyPairMeta {
  final String keyId; // uuid v4
  final DateTime createdAt;

  const CombinedKeyPairMeta({required this.keyId, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'keyId': keyId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CombinedKeyPairMeta.fromJson(Map<String, dynamic> json) =>
      CombinedKeyPairMeta(
        keyId: json['keyId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// A lightweight descriptor for keys stored in secure storage (seed only).
/// Private keys are not exposed here. This structure contains only public
/// keys and metadata.
class CombinedKeyPairDescriptor {
  final PublicIdentity publicIdentity;
  final CombinedKeyPairMeta meta;

  const CombinedKeyPairDescriptor({
    required this.publicIdentity,
    required this.meta,
  });

  Map<String, dynamic> toJson() => {
        'publicIdentity': publicIdentity.toJson(),
        'meta': meta.toJson(),
      };

  factory CombinedKeyPairDescriptor.fromJson(Map<String, dynamic> json) =>
      CombinedKeyPairDescriptor(
        publicIdentity:
            PublicIdentity.fromJson(json['publicIdentity'] as Map<String, dynamic>),
        meta: CombinedKeyPairMeta.fromJson(json['meta'] as Map<String, dynamic>),
      );
}

// Helpers
String b64url(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');
Uint8List b64urlDecode(String s) {
  // Re-pad if needed
  var out = s;
  while (out.length % 4 != 0) {
    out += '=';
  }
  return Uint8List.fromList(base64Url.decode(out));
}
