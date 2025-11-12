import 'dart:async';
import 'dart:io';

import 'package:pocket_coach/tools/docs_builder.dart';

typedef VoidCallback = void Function();

class _Debouncer {
  final Duration delay;
  VoidCallback? _action;
  Timer? _timer;
  _Debouncer(this.delay);

  void call(VoidCallback action) {
    _action = action;
    _timer?.cancel();
    _timer = Timer(delay, () => _action?.call());
  }

  void dispose() => _timer?.cancel();
}

bool _isInterestingPath(String path) {
  final p = path.replaceAll('\\', '/');
  // Ignore common noisy/large dirs
  const ignoreDirs = [
    '/.git/', '/.dart_tool/', '/build/', '/.idea/', '/.vscode/', '/sdk_release/', '/perf_reports/'
  ];
  for (final d in ignoreDirs) {
    if (p.contains(d)) return false;
  }
  // Only react to files in these roots or with interesting extensions
  final interestingRoots = [
    '/lib/', '/docs/', '/api/', '/tests/', '/nodescript/', '/assets/'
  ];
  final hasRoot = interestingRoots.any((r) => p.contains(r));
  if (!hasRoot) {
    // Allow root files like README.md or pubspec.yaml
    if (!p.endsWith('README.md') && !p.endsWith('pubspec.yaml') && !p.endsWith('analysis_options.yaml')) {
      return false;
    }
  }

  const exts = ['.md', '.markdown', '.dart', '.yaml', '.yml', '.js', '.ts', '.sh', '.ps1'];
  return exts.any((e) => p.toLowerCase().endsWith(e));
}

Future<void> main(List<String> args) async {
  stdout.writeln('[docs-watch] Watching for changes. Press Ctrl+C to stop.');

  final debouncer = _Debouncer(const Duration(milliseconds: 600));
  var building = false;
  var pending = false;

  Future<void> runBuild() async {
    if (building) {
      pending = true; // run again after current build
      return;
    }
    building = true;
    final start = DateTime.now();
    stdout.writeln('[docs-watch] Change detected. Rebuilding docs...');
    try {
      final res = await DocsBuilder().generateAll(write: true);
      final dur = DateTime.now().difference(start);
      stdout.writeln('[docs-watch] Done in ${dur.inMilliseconds}ms. '
          'wrote=${res.written.length} validated=${res.validatedLinks.length}');
      if (res.errors.isNotEmpty) {
        stderr.writeln('[docs-watch] ${res.errors.length} error(s):');
        for (final e in res.errors) {
          stderr.writeln(' - $e');
        }
      }
    } catch (e, st) {
      stderr.writeln('[docs-watch] Build error: $e');
      stderr.writeln(st);
    } finally {
      building = false;
      if (pending) {
        pending = false;
        // schedule another run after brief debounce
        debouncer(() => runBuild());
      }
    }
  }

  // Kick an initial build so docs are in sync when watcher starts
  await runBuild();

  // Watch the whole repo recursively, filter by path
  final root = Directory('.');
  final stream = root.watch(recursive: true, events: FileSystemEvent.all);
  final sub = stream.listen((evt) {
    final p = evt.path;
    if (_isInterestingPath(p)) {
      debouncer(runBuild);
    }
  }, onError: (e) {
    stderr.writeln('[docs-watch] watcher error: $e');
  });

  // Keep the process alive
  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\n[docs-watch] Stopping...');
    await sub.cancel();
    debouncer.dispose();
    exit(0);
  });

  // Also handle SIGTERM if supported
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) async {
      stdout.writeln('\n[docs-watch] Stopping (SIGTERM)...');
      await sub.cancel();
      debouncer.dispose();
      exit(0);
    });
  }
}
