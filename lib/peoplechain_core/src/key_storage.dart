import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as fss;

import 'models/keypair.dart';
import 'utils/shamir.dart';

abstract class SecureStorageDriver {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

class FlutterSecureStorageDriver implements SecureStorageDriver {
  final fss.FlutterSecureStorage _inner;

  FlutterSecureStorageDriver()
      : _inner = fss.FlutterSecureStorage(
          aOptions: const fss.AndroidOptions(
            encryptedSharedPreferences: true,
          ),
          // Use defaults for iOS/macOS/Web; web uses localStorage under the hood
        );

  @override
  Future<void> delete({required String key}) async {
    await _inner.delete(key: key);
  }

  @override
  Future<String?> read({required String key}) async {
    return await _inner.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) async {
    await _inner.write(key: key, value: value);
  }
}

/// A resilient storage driver that safely falls back to in-memory storage
/// if flutter_secure_storage throws (e.g., in restricted web environments).
class SafeSecureStorageDriver implements SecureStorageDriver {
  final FlutterSecureStorageDriver _primary = FlutterSecureStorageDriver();
  final InMemorySecureStorageDriver _fallback = InMemorySecureStorageDriver();

  @override
  Future<void> delete({required String key}) async {
    try {
      await _primary.delete(key: key);
    } catch (_) {
      await _fallback.delete(key: key);
    }
  }

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _primary.read(key: key);
    } catch (_) {
      // Fall back silently to in-memory store
      return await _fallback.read(key: key);
    }
  }

  @override
  Future<void> write({required String key, required String value}) async {
    try {
      await _primary.write(key: key, value: value);
    } catch (_) {
      await _fallback.write(key: key, value: value);
    }
  }
}

class InMemorySecureStorageDriver implements SecureStorageDriver {
  final Map<String, String> _store = {};

  @override
  Future<void> delete({required String key}) async {
    _store.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => _store[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }
}

class KeyStorage {
  static const _seedKey = 'peoplechain_master_seed_v1';
  static const _descKey = 'peoplechain_keypair_descriptor_v1';

  final SecureStorageDriver _driver;

  KeyStorage({SecureStorageDriver? driver})
      : _driver = driver ?? (kIsWeb ? SafeSecureStorageDriver() : FlutterSecureStorageDriver());

  Future<void> saveSeed(Uint8List seed) async {
    final encoded = base64Url.encode(seed).replaceAll('=', '');
    await _driver.write(key: _seedKey, value: encoded);
  }

  Future<Uint8List?> loadSeed() async {
    final v = await _driver.read(key: _seedKey);
    if (v == null) return null;
    var out = v;
    while (out.length % 4 != 0) {
      out += '=';
    }
    return Uint8List.fromList(base64Url.decode(out));
  }

  Future<void> clearSeed() async {
    await _driver.delete(key: _seedKey);
  }

  Future<void> saveDescriptor(CombinedKeyPairDescriptor desc) async {
    final jsonStr = jsonEncode(desc.toJson());
    await _driver.write(key: _descKey, value: jsonStr);
  }

  Future<CombinedKeyPairDescriptor?> loadDescriptor() async {
    final v = await _driver.read(key: _descKey);
    if (v == null) return null;
    try {
      final map = jsonDecode(v) as Map<String, dynamic>;
      return CombinedKeyPairDescriptor.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDescriptor() async {
    await _driver.delete(key: _descKey);
  }

  // Backup & Restore via Shamir Secret Sharing
  Future<List<String>> backupToShards({
    required int threshold,
    required int shares,
  }) async {
    final seed = await loadSeed();
    if (seed == null) {
      throw StateError('No seed stored');
    }
    final splitShares = Shamir.split(seed, threshold, shares);
    return splitShares.map(Shamir.encodeShare).toList(growable: false);
  }

  Future<void> restoreFromShards(List<String> encodedShares) async {
    if (encodedShares.length < 2) {
      throw ArgumentError('At least 2 shares are required');
    }
    final shares = encodedShares.map(Shamir.decodeShare).toList();
    final seed = Shamir.combine(shares);
    await saveSeed(seed);
  }
}
