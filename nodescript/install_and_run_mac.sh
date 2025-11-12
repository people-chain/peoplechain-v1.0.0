#!/usr/bin/env bash
set -euo pipefail

PORT=8080
LABEL="com.peoplechain.discovery"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_JS="$SCRIPT_DIR/discovery_server.js"
if [[ ! -f "$SERVER_JS" ]]; then
  echo "discovery_server.js not found at $SERVER_JS" >&2
  exit 1
fi

NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
  echo "Node.js not found in PATH. Please install Node.js" >&2
  exit 1
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${SERVER_JS}</string>
    <string>--port</string>
    <string>${PORT}</string>
  </array>
  <key>WorkingDirectory</key><string>${SCRIPT_DIR}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/peoplechain-discovery.out</string>
  <key>StandardErrorPath</key><string>/tmp/peoplechain-discovery.err</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"
launchctl start "$LABEL" 2>/dev/null || true

echo "Discovery server starting on port $PORT"
URL="http://127.0.0.1:$PORT/"
echo "Open: $URL"
open "$URL" >/dev/null 2>&1 || true