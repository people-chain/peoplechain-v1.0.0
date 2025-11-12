# PeopleChain API Examples

Run these from the repo root using Flutter or Dart. The Monitor Server is available on Linux desktop; on other platforms, adapt as needed.

Prerequisites
- Flutter SDK installed locally
- Optional: Discovery relay (nodescript/discovery_server.js) running: `node nodescript/discovery_server.js`

Examples
- example_send_text.dart
  - Run two instances on the same LAN or with the discovery relay.
  - Command: `flutter run -d linux -t api/examples/example_send_text.dart --dart-define=PEOPLECHAIN_DISCOVERY_HOST=127.0.0.1 --dart-define=PEOPLECHAIN_DISCOVERY_PORT=8081`
  - Paste the peer’s ed25519 key into the other instance.

- example_send_media.dart
  - Same run instructions as send_text; replace peer key and observe media tx id output.

- example_query_chain.dart
  - Single-instance: `flutter run -d linux -t api/examples/example_query_chain.dart`

- example_rest_client.dart
  - Start a Linux node with Monitor Server enabled (default in this repo).
  - `dart run api/examples/example_rest_client.dart`

- example_js_shortcut.html + example_js_client.js
  - Open example_js_shortcut.html in a browser on the same machine as the Monitor Server.
  - Click buttons to exercise REST and WS endpoints.

- EXPLORER.html
  - Served by the Monitor Server at http://127.0.0.1:8080/api/EXPLORER.html
