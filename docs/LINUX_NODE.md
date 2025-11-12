# PeopleChain Linux Node (Headless) + systemd

This project ships a headless entrypoint to run a full PeopleChain node on Linux.

Contents
- Entry point: bin/peoplechain_node.dart
- Systemd unit: docs/peoplechain.service
- Data dir: ~/.peoplechain/ (keys) and Isar DB in default location
- Logs: /var/log/peoplechain/node.log (fallback: ~/.peoplechain/node.log)

Build and run manually
1) Install Dart SDK 3.x
2) From project root:

   dart pub get
   dart run pocket_coach:peoplechain_node

systemd setup (root)
1) Create user/group:

   useradd --system --home /var/lib/peoplechain --shell /usr/sbin/nologin peoplechain || true
   install -d -o peoplechain -g peoplechain /var/log/peoplechain
   install -d -o peoplechain -g peoplechain /var/lib/peoplechain

2) Install unit:

   install -m 0644 docs/peoplechain.service /etc/systemd/system/peoplechain.service
   systemctl daemon-reload
   systemctl enable --now peoplechain.service

Notes
- The headless node uses Isar as storage and automatic P2P discovery (mDNS/WebRTC broadcast on web equivalent is not applicable on server).
- Keys are stored in ~/.peoplechain/ using flutter_secure_storage-compatible encoding; ensure home for the service user is writable.
- Adjust ExecStart to a compiled snapshot/binary if desired (dart compile exe ...).
