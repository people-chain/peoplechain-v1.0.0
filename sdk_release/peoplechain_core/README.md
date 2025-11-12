# peoplechain_core

On-device, decentralized chat ledger for Flutter/Dart apps.

Features
- Deterministic Ed25519/X25519 keypairs stored via platform secure storage
- Isar-backed storage (schemas checked in; no build_runner at runtime)
- WebRTC DataChannel transport (manual/QR pairing)
- mDNS LAN discovery (mobile/Desktop)
- AES-GCM-256 chunk encryption for media

Install (local path)
dependencies:
  peoplechain_core:
    path: ./sdk_release/peoplechain_core

Import
import 'package:peoplechain_core/peoplechain_core.dart';

Quick start
final node = PeopleChainNode();
await node.startNode(const NodeConfig(alias: 'Alice'));
final info = await node.getNodeInfo();

See docs/USAGE.md and docs/API.md in the repository root for full details.
