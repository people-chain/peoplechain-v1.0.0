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

"$(dirname "$0")/stop_mac.sh" --port "$PORT" || true

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST" || true

echo "Uninstall complete."