# Discovery Node • USAGE

The Discovery Node is a single-file HTTP relay (nodescript/discovery_server.js). It enables signaling for WebRTC peers.

### Start on Linux
```bash
cd nodescript
./install_and_run_linux.sh -p 8081 -H 0.0.0.0
```

### Start on Windows
```powershell
cd nodescript
powershell -ExecutionPolicy Bypass -File .\install_and_run_windows.ps1 -Port 8081 -HostName 0.0.0.0
```

Clients auto-discover the relay when reachable. No app code changes required.
