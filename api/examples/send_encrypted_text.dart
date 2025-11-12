import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

Future<void> main() async {
  final node = PeopleChainNode();
  await node.startNodeWithProgress(const NodeConfig(alias: 'Alice'));
  await node.enableAutoMode();

  node.onTxReceived().listen((e) async {
    final text = await node.resolveText(e.tx);
    print('RX: ${text ?? e.tx.payload.type}');
  });

  // Replace with discovered peer ed25519 key
  final bobEd25519 = 'REPLACE_ME_BASE64URL_ED25519';
  final res = await node.sendMessage(toPubKey: bobEd25519, text: 'Hello from PeopleChain');
  print('TX sent: ${res.ok} id=${res.txId}');
}
