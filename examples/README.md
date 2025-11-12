PeopleChain API Examples

This folder contains minimal, ready-to-run client examples that talk to the Node Monitor server shipped with PeopleChain.

Default base URL: http://127.0.0.1:8081
Override with the BASE_URL environment variable, for example: BASE_URL=http://192.168.1.50:8081

Endpoints exposed by the monitor
- GET /api/info — node id, alias, keys, tip height
- GET /api/tip — tip height only
- GET /api/peers?limit=100 — recent peers
- GET /api/blocks?from=tip&count=20 — recent blocks window
- GET /api/block/{block_id} — block by id
- GET /api/tx/{tx_id} — transaction by id
- WebSocket /ws — send {"type":"get_info"} to receive node info and listen for events: metric, log, peer, block

Examples included
- python/peoplechain_api_example.py
- javascript/node/peoplechain_api_example.mjs
- java/PeopleChainApiExample.java
- curl/examples.sh

Notes
- Ensure your node is running with the monitor enabled. On Linux desktop builds, run with:
  flutter run -d linux --dart-define=PEOPLECHAIN_MONITOR_PORT=8081
  To expose to LAN: add --dart-define=PEOPLECHAIN_MONITOR_LAN=1 and use your LAN IP in BASE_URL.
