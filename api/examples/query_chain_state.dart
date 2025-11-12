import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

Future<void> main() async {
  final node = PeopleChainNode();
  await node.startNode(const NodeConfig(alias: 'Inspector'));

  final info = await node.getNodeInfo();
  print('Node: ${info.nodeId} tip=${info.tipHeight}');

  final tip = await node.tipHeight();
  if (tip >= 0) {
    final b = await node.getBlockByHeight(tip);
    print('Latest block: ${b?.header.blockId} tx=${b?.txIds.length}');
  }
}
