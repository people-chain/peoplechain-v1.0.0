import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

// Run two instances (different terminals) to exchange a message via discovery/WebRTC.
// Optionally pass --dart-define=PEOPLECHAIN_DISCOVERY_HOST=127.0.0.1 --dart-define=PEOPLECHAIN_DISCOVERY_PORT=8081
Future<void> main() async {
  final node = PeopleChainNode();
  await node.startNodeWithProgress(const NodeConfig(alias: 'ExampleSender'));
  await node.enableAutoMode();

  node.onTxReceived().listen((e) async {
    final text = await node.resolveText(e.tx);
    print('RX: ${text ?? e.tx.payload.type}');
  });

  // Replace with discovered peer ed25519 key printed by the other instance
  final peerEd25519 = 'REPLACE_ME_BASE64URL_ED25519';
  final res = await node.sendMessage(toPubKey: peerEd25519, text: 'Hello from example_send_text');
  print('TX sent ok=${res.ok} id=${res.txId}');
}
