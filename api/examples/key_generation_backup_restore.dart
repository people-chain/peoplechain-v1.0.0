import 'package:pocket_coach/peoplechain_core/peoplechain_core.dart';

Future<void> main() async {
  final crypto = CryptoManager();
  if (!await crypto.hasKeys()) {
    await crypto.generateAndStoreKeys();
    print('Generated new keypair');
  }
  final desc = await crypto.getDescriptor();
  print('Node ID: ${desc?.meta.keyId}');

  final shards = await crypto.storage.backupToShards(shares: 5, threshold: 3);
  print('Backup shards (store securely):');
  for (final s in shards) {
    print('- $s');
  }

  // Simulate restore using threshold shards
  final restore = shards.take(3).toList();
  await crypto.storage.restoreFromShards(restore);
  print('Restore complete');
}
