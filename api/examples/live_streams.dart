import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

Future<void> main() async {
  final node = PeopleChainNode();
  await node.startNode(const NodeConfig(alias: 'Observer'));
  await node.enableAutoMode();

  node.onSyncState().listen((s) => print('Sync: $s'));
  node.onPeerDiscovered().listen((p) => print('Peer: ${p.nodeId} via ${p.transports}'));
  node.onBlockAdded().listen((b) => print('Block: ${b.block.header.height}'));
  node.onTxReceived().listen((t) => print('Tx: ${t.tx.txId}'));
}
