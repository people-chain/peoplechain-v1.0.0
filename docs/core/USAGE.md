# PeopleChain Core • USAGE

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

See also: [../sdk/USAGE.md](../sdk/USAGE.md)
