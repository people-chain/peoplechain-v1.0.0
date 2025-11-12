import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'isar_models.dart';

/// Centralized Isar opener with all schemas so multiple modules share one instance.
class IsarFactory {
  static Isar? _instance;
  // Serialize concurrent open attempts to avoid double-opening the same instance.
  // Use a Completer-based latch so only one doOpen() runs at a time.
  static Future<Isar>? _opening;
  static Completer<Isar>? _openCompleter;

  static const int _webSchemaVersion = 2; // bump when schema ids/index ids change
  static const int _ioSchemaVersion = 3; // bump when IO schema ids/index ids change

  static Future<Isar> open({String? directoryPath, String name = 'peoplechain'}) async {
    // Allow overriding DB name/dir for power users and multi-instance testing on desktop.
    final envName = const String.fromEnvironment('PEOPLECHAIN_DB_NAME');
    final resolvedName = (envName.isNotEmpty ? envName : (Platform.environment['PEOPLECHAIN_DB_NAME'] ?? '')).trim();
    if (resolvedName.isNotEmpty) {
      name = resolvedName;
    }
    if (_instance != null && _instance!.isOpen) return _instance!;

    // If an open is already in progress, await it. This prevents races where
    // Isar.getInstance(name) might surface a partially initialized object.
    if (_opening != null) {
      return _opening!;
    }

    // Important for Flutter desktop hot-restart:
    // The native Isar instance may remain open in-process while Dart statics reset.
    // Attempt to retrieve an existing instance before trying to open a new one,
    // otherwise Isar will throw "instance has been already opened".
    if (!kIsWeb) {
      final existing = Isar.getInstance(name);
      if (existing != null && existing.isOpen) {
        debugPrint('[IsarFactory] Reusing existing Isar instance name=$name');
        _instance = existing;
        return existing;
      }
    }

    Future<Isar> doOpen() async {
      // On web: do NOT pass a directory; IndexedDB is used automatically.
      // On mobile/desktop: create an app-specific directory for the database files.
      if (kIsWeb) {
        // Derive a web-specific DB name to avoid schema mismatch with older IndexedDB data
        final webName = '${name}_v$_webSchemaVersion';
        try {
          // Important: do not pass a directory on web (asserts inside Isar)
          // Inspector is disabled on web for stability
          debugPrint('[IsarFactory] Opening Isar on web with name=$webName');
          _instance = await Isar.open(
            [
              ChunkEntitySchema,
              TxEntitySchema,
              BlockEntitySchema,
              ConversationEntitySchema,
              PeerEntitySchema,
            ],
            name: webName,
            // Web ignores directory; required by the API, so pass empty string.
            directory: '',
            inspector: false,
          );
        } catch (e) {
          // Attempt a fresh name fallback to bypass potential old/broken IndexedDB state
          final fallbackName = '${webName}_fresh';
          debugPrint('[IsarFactory] Web Isar open failed: $e. Retrying with name=$fallbackName');
          try {
            _instance = await Isar.open(
              [
                ChunkEntitySchema,
                TxEntitySchema,
                BlockEntitySchema,
                ConversationEntitySchema,
                PeerEntitySchema,
              ],
              name: fallbackName,
              directory: '',
              inspector: false,
            );
          } catch (e2) {
            // Re-throw with a friendlier message for the Startup Progress screen
            throw IsarError('Failed to initialize local database on Web. Try clearing site data (Application > Storage > Clear site data) and reload. Original error: $e2');
          }
        }
      } else {
        String? dir;
        // Directory priority: explicit argument > dart-define/env override > default app dir
        final envDir = const String.fromEnvironment('PEOPLECHAIN_DB_DIR');
        final resolvedDir = (envDir.isNotEmpty ? envDir : (Platform.environment['PEOPLECHAIN_DB_DIR'] ?? '')).trim();
        if (directoryPath != null) {
          dir = directoryPath;
        } else if (resolvedDir.isNotEmpty) {
          dir = resolvedDir;
        } else {
          final Directory d = await getApplicationDocumentsDirectory();
          final sub = Directory('${d.path}/$name');
          if (!await sub.exists()) {
            await sub.create(recursive: true);
          }
          dir = sub.path;
        }

        debugPrint('[IsarFactory] Opening Isar on IO name=$name dir=$dir');
        try {
          _instance = await Isar.open(
            [
              ChunkEntitySchema,
              TxEntitySchema,
              BlockEntitySchema,
              ConversationEntitySchema,
              PeerEntitySchema,
            ],
            name: name,
            directory: dir,
            inspector: false,
          );
          debugPrint('[IsarFactory] Isar opened successfully name=$name dir=$dir');
        } catch (e) {
          // Handle common schema mismatch/corruption cases by falling back to a new DB name.
          final msg = e.toString();
          final looksLikeSchemaMismatch = msg.contains('Collection id is invalid') ||
              msg.contains('IllegalArg') ||
              msg.contains('Unknown collection') ||
              msg.contains('SchemaMismatch') ||
              msg.contains('Unknown property');
          if (looksLikeSchemaMismatch) {
            final fallbackName = '${name}_v$_ioSchemaVersion';
            // Place the fallback DB in its own directory alongside the original.
            String fallbackDir;
            if (directoryPath != null || resolvedDir.isNotEmpty) {
              // If the caller provided a directory, keep using it but isolate by name only.
              fallbackDir = dir!;
            } else {
              final Directory d = await getApplicationDocumentsDirectory();
              final sub = Directory('${d.path}/$fallbackName');
              if (!await sub.exists()) {
                await sub.create(recursive: true);
              }
              fallbackDir = sub.path;
            }
            debugPrint('[IsarFactory] IO Isar open failed: $e. Retrying with name=$fallbackName dir=$fallbackDir');
            try {
              _instance = await Isar.open(
                [
                  ChunkEntitySchema,
                  TxEntitySchema,
                  BlockEntitySchema,
                  ConversationEntitySchema,
                  PeerEntitySchema,
                ],
                name: fallbackName,
                directory: fallbackDir,
                inspector: false,
              );
              debugPrint('[IsarFactory] Isar opened successfully name=$fallbackName dir=$fallbackDir');
            } catch (e2) {
              // As a last resort, create a uniquely named fresh DB to bypass any stale files.
              final ts = DateTime.now().millisecondsSinceEpoch;
              final freshName = '${fallbackName}_fresh_$ts';
              String freshDir;
              if (directoryPath != null || resolvedDir.isNotEmpty) {
                freshDir = dir!; // isolate by name only when explicit dir is used
              } else {
                final Directory d = await getApplicationDocumentsDirectory();
                final sub = Directory('${d.path}/$freshName');
                if (!await sub.exists()) {
                  await sub.create(recursive: true);
                }
                freshDir = sub.path;
              }
              debugPrint('[IsarFactory] Fallback open failed: $e2. Retrying with name=$freshName dir=$freshDir');
              _instance = await Isar.open(
                [
                  ChunkEntitySchema,
                  TxEntitySchema,
                  BlockEntitySchema,
                  ConversationEntitySchema,
                  PeerEntitySchema,
                ],
                name: freshName,
                directory: freshDir,
                inspector: false,
              );
              debugPrint('[IsarFactory] Isar opened successfully name=$freshName dir=$freshDir');
            }
          } else {
            rethrow;
          }
        }
      }

      return _instance!;
    }

    // Create a latch before any async gap so all concurrent callers await the same Future
    final completer = Completer<Isar>();
    _openCompleter = completer;
    _opening = completer.future;
    () async {
      try {
        // Re-check whether another thread opened the instance just before us
        if (!kIsWeb) {
          final existing = Isar.getInstance(name);
          if (existing != null && existing.isOpen) {
            debugPrint('[IsarFactory] Reusing existing Isar instance name=$name');
            _instance = existing;
            completer.complete(existing);
            return;
          }
        }

        final opened = await doOpen();
        completer.complete(opened);
      } catch (e, st) {
        final msg = e.toString();
        final looksLikeSchemaMismatch = msg.contains('Collection id is invalid') ||
            msg.contains('IllegalArg') ||
            msg.contains('Unknown collection') ||
            msg.contains('SchemaMismatch') ||
            msg.contains('Unknown property');

        // Only try to recover an existing instance for non-schema errors.
        if (!looksLikeSchemaMismatch) {
          // Be very defensive: on any open failure, try to reuse an instance that may
          // have been opened by a parallel caller (hot-restart races, multiple services).
          try {
            final existing = Isar.getInstance(name);
            if (existing != null && existing.isOpen) {
              debugPrint('[IsarFactory] Recovered existing Isar after open failure name=$name e=$e');
              _instance = existing;
              completer.complete(existing);
              return;
            }
          } catch (_) {}
        }

        // Enhance the error message for the common double-open case across processes.
        if (msg.contains('already opened') || msg.contains('already open')) {
          debugPrint('[IsarFactory] Open failed because instance is already opened elsewhere name=$name');
          completer.completeError(IsarError(
            'Isar database "$name" is already in use in this or another running PeopleChain process. '
            'Close any existing app instance (including background services) and try again.\n'
            'If you used flutter run and detached (key "d"), kill the previous binary first.\n'
            'Original error: $msg',
          ));
          return;
        }

        completer.completeError(e, st);
      } finally {
        _opening = null;
        _openCompleter = null;
      }
    }();

    return _opening!;
  }
}
