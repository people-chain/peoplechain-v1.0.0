// Stubbed JS bridge for non-web platforms.

import '../peoplechain_core/peoplechain_core.dart' as pc;

bool get jsApiSupported => false;

void registerJsApi(pc.PeopleChainNode node) {}

void unregisterJsApi() {}

Future<Map<String, dynamic>> sendTestPostMessage(Map<String, dynamic> request) async {
  throw UnsupportedError('JS bridge not supported on this platform');
}
