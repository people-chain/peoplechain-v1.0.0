# Production Verification Campaign — Runbook

This folder contains scripts and test harnesses to reproduce the end-to-end verification on 3–5 heterogeneous devices.

Device matrix
- Android phone (Android 13/14/15)
- Linux desktop/laptop
- Web browser tab/PWA (Chrome/Edge)
- Optional: Second Android or a Windows laptop for 4th/5th device

Pre-setup
1) Start the Discovery Relay on a reachable host:
   node nodescript/discovery_server.js
   (Defaults to 0.0.0.0:8081; you can override PORT/host via env vars.)
2) Ensure all devices can reach the relay host and port.
3) Build and install the app on devices (or use web preview for browser).

Environment flags for clients
- Set via Flutter: --dart-define=PEOPLECHAIN_DISCOVERY_HOST=RELAY_IP --dart-define=PEOPLECHAIN_DISCOVERY_PORT=8081

Automated pieces
- Dart integration tests simulate the relay and verify auto-connect flows: see test/integration/discovery_autoconnect_test.dart
- Scripts below help collect logs/metrics during manual multi-device runs.

Scenarios
1) Auto-connect test
   - Start all clients within 10 seconds.
   - Verify Synced within 30 seconds on each.
   - Capture monitor logs (Linux) and device logs (adb logcat filtered by PeopleChain).

2) Message round-trip
   - Send 100 small texts and 10 media (200KB images) across pairs.
   - Record latencies and export CSV via the app dashboard or monitor endpoints.

3) Block sync & reconciliation
   - Use test harness (lib/testing/test_harness.dart) to inject conflicting blocks on one node.
   - Observe resolution and record merkle proof checks.

4) Resilience & reconnect
   - Android: Airplane mode for 2 minutes; then resume.
   - Linux: Kill the process and restart the app; confirm catch-up sync.

5) Resource profiling (1 hour)
   - Collect CPU, memory, battery (Android) every minute; see scripts.

Artifacts
- Store raw logs and metrics under perf_reports/production/<DATE>/*
- Place short screen captures under perf_reports/production/videos/*
