import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart' as md;

class DocsBuildResult {
  final List<String> written;
  final List<String> validatedLinks;
  final List<String> errors;
  DocsBuildResult({required this.written, required this.validatedLinks, required this.errors});
}

/// DocsBuilder regenerates Markdown content and HTML mirrors for the project.
/// - Ensures USAGE.md for core modules
/// - Rebuilds README.md (root) and README.html
/// - Converts all .md under repo (README.md, docs/**/*.md, api/**/*.md, tests/**/*.md) to .html next to them
/// - Validates relative links point to existing files (md or html)
class DocsBuilder {
  final DateTime now = DateTime.now().toUtc();

  Future<DocsBuildResult> generateAll({bool write = true}) async {
    final written = <String>[];
    final errors = <String>[];
    final validated = <String>[];

    // 1) Ensure module USAGE docs exist
    written.addAll(await _ensureModuleDocs());

    // 2) Refresh root README.md
    final readmeMd = _rootReadme();
    if (write) {
      await File('README.md').writeAsString(readmeMd);
      written.add('README.md');
    }

    // Collect all markdown files to convert
    final mdFiles = await _collectMarkdownFiles();
    // Convert to HTML
    for (final f in mdFiles) {
      try {
        final html = _toHtml(await File(f).readAsString());
        final target = f.replaceAll(RegExp(r'\.md\\$'), '.html');
        final t = f.endsWith('.md') ? f.substring(0, f.length - 3) + '.html' : f + '.html';
        if (write) {
          await File(t).writeAsString(html);
          written.add(t);
        }
      } catch (e) {
        errors.add('Failed to convert $f: $e');
      }
    }

    // Also mirror README.md as README.html
    try {
      final rootMd = await File('README.md').readAsString();
      final html = _toHtml(rootMd);
      if (write) {
        await File('README.html').writeAsString(html);
        written.add('README.html');
      }
    } catch (e) {
      errors.add('Failed to convert README.md: $e');
    }

    // Validate links across Markdown files
    for (final f in mdFiles) {
      final text = await File(f).readAsString();
      final links = _extractMdLinks(text);
      for (final link in links) {
        if (link.startsWith('http://') || link.startsWith('https://') || link.startsWith('#')) {
          validated.add('$f -> $link');
          continue;
        }
        final target = _resolveRelative(File(f).parent.path, link);
        if (await File(target).exists()) {
          validated.add('$f -> $link');
        } else {
          // Try .html if .md
          if (link.endsWith('.md')) {
            final h = target.substring(0, target.length - 3) + '.html';
            if (await File(h).exists()) {
              validated.add('$f -> $link');
              continue;
            }
          }
          errors.add('Broken link in $f: $link');
        }
      }
    }

    // Write a build report
    if (write) {
      final report = StringBuffer()
        ..writeln('Docs build @ ${now.toIso8601String()}')
        ..writeln('Written:')
        ..writeln(written.map((e) => '- $e').join('\n'))
        ..writeln('\nValidated Links: ${validated.length}')
        ..writeln('\nErrors:')
        ..writeln(errors.isEmpty ? 'None' : errors.map((e) => '- $e').join('\n'));
      final rptFile = File('docs/build_report.txt');
      await rptFile.parent.create(recursive: true);
      await rptFile.writeAsString(report.toString());
      written.add('docs/build_report.txt');
    }

    return DocsBuildResult(written: written, validatedLinks: validated, errors: errors);
  }

  Future<List<String>> _ensureModuleDocs() async {
    final out = <String>[];
    final entries = <String, String>{
      'docs/core/USAGE.md': _coreUsageMd(),
      'docs/monitor/USAGE.md': _monitorUsageMd(),
      'docs/discovery/USAGE.md': _discoveryUsageMd(),
      'docs/sdk/USAGE.md': _sdkUsageMd(),
    };
    for (final e in entries.entries) {
      final f = File(e.key);
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value);
      out.add(e.key);
    }
    return out;
  }

  Future<List<String>> _collectMarkdownFiles() async {
    final res = <String>[];
    Future<void> walk(String dir) async {
      final d = Directory(dir);
      if (!await d.exists()) return;
      await for (final ent in d.list(recursive: true, followLinks: false)) {
        if (ent is File && ent.path.toLowerCase().endsWith('.md')) {
          res.add(ent.path);
        }
      }
    }
    await walk('docs');
    await walk('api');
    await walk('tests');
    // include root README.md implicitly via special case
    return res;
  }

  List<String> _extractMdLinks(String text) {
    final reg = RegExp(r'\[[^\]]*\]\(([^)]+)\)');
    return reg.allMatches(text).map((m) => m.group(1)!).toList();
  }

  String _resolveRelative(String baseDir, String href) {
    final norm = href.split('#').first; // drop anchors
    final p = Uri.parse(norm);
    if (p.isAbsolute) return href;
    return File('${baseDir.isEmpty ? '.' : baseDir}/${p.path}').path;
  }

  String _toHtml(String markdown) {
    final body = md.markdownToHtml(markdown, extensionSet: md.ExtensionSet.gitHubWeb);
    return '<!doctype html>\n<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
        '<style>body{font-family:system-ui,Segoe UI,Roboto,Ubuntu,Arial;max-width:860px;margin:40px auto;padding:0 16px;line-height:1.6;background:#0b0d10;color:#e8eaed} pre{background:#0f1217;padding:12px;border-radius:8px;overflow:auto} code{font-family:ui-monospace,Menlo,Consolas,monospace}</style>'
        '</head><body>'
        '$body'
        '</body></html>';
  }

  String _rootReadme() {
    return '''# PeopleChain

PeopleChain is an on-device, peer-to-peer data network for secure, resilient communication without central servers. It powers end-to-end encrypted chat, distributed data sync, and edge IoT collaboration using compact blocks and WebRTC transports.

## Vision and Goals
- Privacy-first communication with keys that never leave the device
- Offline-first operation with automatic discovery and healing
- No mandatory cloud: run locally, on LAN, or across the Internet
- Simple SDK that works on Android, Web, and Linux

## Architecture
- Core Node (lib/peoplechain_core): local chain, tx/block store, sync engine
- Discovery Node (nodescript): zero-dependency HTTP relay for WebRTC signaling
- WebRTC Transport: fully P2P data channel for sync and messaging
- P2P Manager: multi-transport discovery (Discovery relay, mDNS, BLE, Wi‑Fi Direct, Nearby)
- Node Monitor Server: lightweight embedded dashboard and API explorer

## Installation and Usage

### Android
1. Build the Flutter app (Android target). The node runs on-device.
2. Start a Discovery Node on your PC if you want cross-subnet rendezvous: see [docs/discovery/USAGE.md](docs/discovery/USAGE.md).

### Web
1. Run the Flutter Web build or use Dreamflow preview.
2. Ensure the Discovery Node is reachable from the browser (CORS friendly). See [docs/discovery/USAGE.md](docs/discovery/USAGE.md).

### Linux/Desktop
1. Launch the app; Node Monitor Server binds on 127.0.0.1:8080 and serves a dashboard.
2. Use curl against /api for scripting. See [docs/monitor/USAGE.md](docs/monitor/USAGE.md).

## Real-world Use Cases
- Secure chat and media with content-based chunking and re-assembly
- Distributed sensor data capture and local-first analytics for IoT
- Air-gapped cyber defense and incident coordination
- LAN collaboration in constrained or disconnected environments

## Developer Guides
- Core Node usage: [docs/core/USAGE.md](docs/core/USAGE.md)
- Discovery Node: [docs/discovery/USAGE.md](docs/discovery/USAGE.md)
- SDK integration patterns: [docs/sdk/USAGE.md](docs/sdk/USAGE.md)
- Node Monitor: [docs/monitor/USAGE.md](docs/monitor/USAGE.md)

---
This README was auto-generated by the DocsBuilder. Edit templates in lib/tools/docs_builder.dart if you need to customize.
''';
  }

  String _coreUsageMd() {
    return '''# PeopleChain Core • USAGE

The Core Node embeds the local chain, message/chunk store, and sync engine. Access it via PeopleChainNode:

```dart
final node = PeopleChainNode();
await node.startNodeWithProgress(const NodeConfig(alias: 'device-1'));
await node.enableAutoMode();
```

### Send a message
```dart
final res = await node.sendMessage(toPubKey: '<recipient-ed25519>', text: 'hello');
```

### Query chain
```dart
final tip = await node.tipHeight();
final block = await node.getBlockByHeight(tip);
```

See also: [docs/sdk/USAGE.md](../sdk/USAGE.md)
''';
  }

  String _monitorUsageMd() {
    return '''# Node Monitor Server • USAGE

The embedded monitor binds on 127.0.0.1:8080 and exposes:

- Web UI dashboard at `/`
- WebSocket live feed at `/ws`
- REST API under `/api/*` including `/api/info`, `/api/peers`, `/api/blocks`, `/api/discovery`

Open the API Explorer at `/api/EXPLORER.html`.
''';
  }

  String _discoveryUsageMd() {
    return '''# Discovery Node • USAGE

The Discovery Node is a single-file HTTP relay (nodescript/discovery_server.js). It enables signaling for WebRTC peers.

### Start on Linux
```bash
cd nodescript
./install_and_run_linux.sh -p 8081 -H 0.0.0.0
```

### Start on Windows
```powershell
cd nodescript
powershell -ExecutionPolicy Bypass -File .\\install_and_run_windows.ps1 -Port 8081 -HostName 0.0.0.0
```

Clients auto-discover the relay when reachable. No app code changes required.
''';
  }

  String _sdkUsageMd() {
    return '''# SDK Integration • USAGE

Minimum bootstrap for Android/Web/Linux:

```dart
final node = PeopleChainNode();
await node.startNodeWithProgress(const NodeConfig(alias: 'producer'));
await node.enableAutoMode();
// Discovery relay is used automatically when reachable
```

For manual QR/SDP flows, see `PeopleChainNode.createOfferPayload()` and `acceptOfferAndCreateAnswer()`.
''';
  }
}
