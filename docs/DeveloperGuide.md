Developer Guide — Building, Architecture, and Environment

1. Repository structure (high level)
- lib/
  - main.dart, theme.dart, home_page.dart — app shell and UX
  - startup_progress_page.dart — animated boot screen with granular steps
  - peoplechain_core/ — SDK source integrated in-app
  - testing/ — Web Testing Dashboard (peers, chain, metrics, explorer, API bridge)
- web/ — PWA manifest and index branding
- android/ — Android project (permissions and app config)
- docs/ — Documentation and diagrams

2. Environment
- Flutter: 3.24+ (Dart 3.6+). This project compiles cleanly against the latest stable (May 2025).
- Platforms: Android, Web. iOS builds are not addressed in this handoff.
- No backend is required. If you later want Firebase or Supabase features in Dreamflow, use the Firebase/Supabase panel to set them up — do not use CLI inside Dreamflow.

3. Building for Web
Option A — Dreamflow Publish
- Use the Publish button (top right) and select Web to deploy. The web/manifest.json and index.html have been branded to “PeopleChain”.

Option B — Local build
- Download code (Menu > Download Code), then:
  - flutter build web --release
  - Host build/web/ on your static hosting (Netlify, Vercel, Firebase Hosting, S3+CloudFront, etc.)
- If serving under a subpath, pass --base-href and ensure web/index.html base is rewritten by Flutter.

4. Building for Android
Option A — Dreamflow Publish
- Use the Publish button and follow the Google Play deployment flow.

Option B — Local build
- Download code, then:
  - Set your applicationId in android/app/build.gradle (default sample id is com.example.counter)
  - Create or import a keystore and configure signingConfigs
  - flutter build appbundle --release (for Play Store) or flutter build apk --release (for side-load testing)
- Android permissions are already declared (INTERNET, NETWORK/WIFI state, WIFI multicast for mDNS, Bluetooth for discovery on supported SDKs).

5. App configuration
- App title: set to “PeopleChain” (MaterialApp.title)
- Launcher icon: configured via flutter_launcher_icons using assets/icons/dreamflow_icon.jpg
- Web PWA branding: web/manifest.json + web/index.html set to PeopleChain and themed with #684F8E

6. Architecture quick tour
- Node lifecycle: open local DB → load/generate keys → TxBuilder init → genesis check → Sync Engine start → P2P discovery and WebRTC start
- Sync: hello/hello_ack → request missing blocks/txs → validate linkage & merkle → commit or request backfill
- Conflict handling: prefer higher height; tie-breaker by lexicographically larger blockId; optional ConsensusHook

7. Dependencies snapshot and guidance
- Core: fl_chart: 0.68.0; isar: ^3.1.0; flutter_secure_storage: ^9.2.2; flutter_webrtc: ^1.x; multicast_dns; flutter_blue_plus (BLE discovery); google_fonts
- Analyzer passes clean with these versions. For production hardening, plan controlled upgrades in a branch (especially flutter_webrtc and flutter_blue_plus) and test Web+Android handshakes.
- Test/build tooling (build_runner, json_serializable, test) are present; keep them pinned in dev_dependencies for package builds (current project compiles fine).

8. Platform notes
- Android: Internet + multicast permissions required for discovery; BLE permissions adapt to SDK version (already declared). If you disable LAN/BLE discovery, you can remove related permissions.
- Web: No special permissions. Pairing uses manual copy/paste or QR payloads.

9. Diagnostics and monitoring
- Web Testing Dashboard (kIsWeb only) includes: Peers, Chain (live), Explorer, API bridge, and metrics charts. Open from the beaker icon in the app bar.

10. Release checklist
- [ ] Verify Create Offer/Accept flows on at least two devices/browsers
- [ ] Confirm Peers/Chain/Explorer show live data during a messaging session
- [ ] Review web manifest icons and theme
- [ ] Set Android applicationId + signing
- [ ] Run flutter test (unit tests under test/)
