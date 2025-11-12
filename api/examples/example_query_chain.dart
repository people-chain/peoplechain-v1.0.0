import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

Future<void> main() async {
  final node = PeopleChainNode();
  await node.startNodeWithProgress(const NodeConfig(alias: 'QueryDemo'));
  final tip = await node.tipHeight();
  print('Tip height: $tip');
  final b = await node.getBlockByHeight(tip);
  print('Tip block id: ${b?.header.blockId}');
}
