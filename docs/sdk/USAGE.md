# SDK Integration • USAGE

Minimum bootstrap for Android/Web/Linux:

```dart
final node = PeopleChainNode();
await node.startNodeWithProgress(const NodeConfig(alias: 'producer'));
await node.enableAutoMode();
// Discovery relay is used automatically when reachable
```

For manual QR/SDP flows, see `PeopleChainNode.createOfferPayload()` and `acceptOfferAndCreateAnswer()`.
