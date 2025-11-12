// Conditional facade for exposing a web-only external testing API.
// On non-web platforms these functions are no-ops.

import '../peoplechain_core/peoplechain_core.dart' as pc;
import 'js_bridge_stub.dart' if (dart.library.html) 'js_bridge_web.dart' as impl;

bool get jsApiSupported => impl.jsApiSupported;

void registerJsApi(pc.PeopleChainNode node) => impl.registerJsApi(node);

void unregisterJsApi() => impl.unregisterJsApi();

Future<Map<String, dynamic>> sendTestPostMessage(Map<String, dynamic> request) => impl.sendTestPostMessage(request);
