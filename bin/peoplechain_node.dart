import 'dart:async';
import 'dart:io';

import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

Future<void> main(List<String> args) async {
  // Simple headless PeopleChain node for Linux.
  final node = PeopleChainNode();
  IOSink? logSink;
  try {
    final logPath = '/var/log/peoplechain/node.log';
    final file = File(logPath);
    await file.parent.create(recursive: true);
    logSink = file.openWrite(mode: FileMode.append);
    logSink.writeln('--- PeopleChain node starting at ${DateTime.now().toUtc().toIso8601String()} ---');
  } catch (_) {
    // Fallback to home directory if /var/log not writable
    try {
      final home = Platform.environment['HOME'] ?? '.';
      final file = File('$home/.peoplechain/node.log');
      await file.parent.create(recursive: true);
      logSink = file.openWrite(mode: FileMode.append);
      logSink!.writeln('--- PeopleChain node starting at ${DateTime.now().toUtc().toIso8601String()} ---');
    } catch (_) {}
  }

  void log(String msg) {
    final line = '[${DateTime.now().toIso8601String()}] $msg';
    stdout.writeln(line);
    try { logSink?.writeln(line); } catch (_) {}
  }

  // Start node using Isar DB and enable auto mode
  try {
    log('Initializing node...');
    await node.startNode(NodeConfig(alias: 'LinuxNode', useIsarDb: true));
    await node.enableAutoMode();
    log('Node started. Waiting for peers...');
  } catch (e) {
    log('Fatal error on startup: $e');
    await logSink?.flush();
    await logSink?.close();
    exit(2);
  }

  node.onPeerDiscovered().listen((p) => log('Peer discovered: ${p.alias ?? p.nodeId} via ${p.transports.join(',')}'));
  node.onBlockAdded().listen((b) => log('Block added: h=${b.block.header.height} id=${b.block.header.blockId.substring(0,8)}...'));
  node.onTxReceived().listen((t) => log('Tx received: ${t.tx.txId.substring(0,8)}...'));

  // Keep process alive
  ProcessSignal.sigterm.watch().listen((_) async {
    log('SIGTERM received, shutting down...');
    await node.stopNode();
    await logSink?.flush();
    await logSink?.close();
    exit(0);
  });
  ProcessSignal.sigint.watch().listen((_) async {
    log('SIGINT received, shutting down...');
    await node.stopNode();
    await logSink?.flush();
    await logSink?.close();
    exit(0);
  });
  // Idle loop
  await Completer<void>().future;
}
