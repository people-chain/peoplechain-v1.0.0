import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'peoplechain_core/peoplechain_core.dart';
import 'peoplechain_core/src/p2p/permissions_android.dart';
// Start local Node Monitor server automatically on IO platforms (Linux/desktop).
import 'peoplechain_core/src/monitor/monitor_bootstrap_stub.dart'
    if (dart.library.io) 'peoplechain_core/src/monitor/monitor_bootstrap_io.dart';
// Android foreground service starter (no-op on non-Android)
import 'platform/android_foreground_stub.dart'
    if (dart.library.io) 'platform/android_foreground_real.dart';
import 'home_page.dart';

class StartupProgressPage extends StatefulWidget {
  const StartupProgressPage({super.key});

  @override
  State<StartupProgressPage> createState() => _StartupProgressPageState();
}

class _StartupProgressPageState extends State<StartupProgressPage> {
  final PeopleChainNode _node = PeopleChainNode();
  StreamSubscription<NodeInitUpdate>? _sub;
  bool _hasError = false;
  String? _errorMessage;
  bool _navigated = false;
  MonitorServerHandle? _monitor;

  final List<_StepDef> _steps = const [
    _StepDef(id: 'open_db', label: 'Opening local database'),
    _StepDef(id: 'secure_storage', label: 'Loading secure storage'),
    _StepDef(id: 'ensure_keys', label: 'Generating or loading node keys'),
    _StepDef(id: 'tx_builder', label: 'Preparing transaction builder'),
    _StepDef(id: 'start_sync', label: 'Starting sync engine'),
    _StepDef(id: 'start_discovery', label: 'Starting discovery / WebRTC services'),
  ];

  late Map<String, NodeInitStatus> _statusById = {
    for (final s in _steps) s.id: NodeInitStatus.pending,
  };

  @override
  void initState() {
    super.initState();
    _beginStartup();
  }

  Future<void> _beginStartup() async {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _statusById = {for (final s in _steps) s.id: NodeInitStatus.pending};
    });
    _sub?.cancel();
    _sub = _node.onInitProgress().listen((evt) {
      setState(() {
        _statusById[evt.id] = evt.status;
        if (evt.status == NodeInitStatus.error) {
          _hasError = true;
          _errorMessage = evt.error;
        }
      });
    });
    try {
      // Android: request discovery-related permissions (includes notification permission on 13+)
      try {
        await requestDiscoveryPermissionsIfNeeded();
      } catch (_) {}

      // Start Foreground Service only after notification permission is handled on Android 13+
      try {
        await startAndroidForegroundService();
      } catch (_) {}

      await _node.startNodeWithProgress(NodeConfig(
        alias: 'Demo',
        // Use in-memory DB on web to avoid Isar 3.x web limitation
        useIsarDb: !kIsWeb,
      ));
      // Enable production auto mode (auto-discovery/bootstrap)
      await _node.enableAutoMode();
      // Start local monitor server (Linux/desktop only). Defaults to 127.0.0.1:8080; set PEOPLECHAIN_MONITOR_LAN=1 to expose on LAN.
      try {
        _monitor = await MonitorBootstrap.start(_node, host: '127.0.0.1', port: 8080);
      } catch (_) {}
      if (mounted && !_hasError && !_navigated) {
        _navigated = true;
        // Navigate to the main home screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomePage(node: _node)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Starting PeopleChain'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _hasError ? 'Startup failed' : 'Initializing node...',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: _steps.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final step = _steps[index];
                      final status = _statusById[step.id] ?? NodeInitStatus.pending;
                      return _StepTile(label: step.label, status: status, colorScheme: colorScheme);
                    },
                  ),
                ),
                if (_hasError) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage ?? 'Unknown error',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _beginStartup,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      SizedBox(width: 8),
                      Text('Working...'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepDef {
  final String id;
  final String label;
  const _StepDef({required this.id, required this.label});
}

class _StepTile extends StatelessWidget {
  final String label;
  final NodeInitStatus status;
  final ColorScheme colorScheme;
  const _StepTile({required this.label, required this.status, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;
    Widget? trailing;

    switch (status) {
      case NodeInitStatus.pending:
        icon = Icons.circle_outlined;
        iconColor = colorScheme.outline;
        trailing = null;
        break;
      case NodeInitStatus.inProgress:
        icon = Icons.hourglass_top;
        iconColor = colorScheme.primary;
        trailing = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case NodeInitStatus.done:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        trailing = Icon(Icons.check, color: Colors.green);
        break;
      case NodeInitStatus.error:
        icon = Icons.error;
        iconColor = colorScheme.error;
        trailing = Icon(Icons.error_outline, color: colorScheme.error);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
