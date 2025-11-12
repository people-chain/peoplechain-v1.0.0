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

echo "Stopping discovery server (port $PORT)..."
launchctl stop "$LABEL" 2>/dev/null || true
launchctl unload "$PLIST" 2>/dev/null || true

if command -v lsof >/dev/null 2>&1; then
  PID="$(lsof -t -i :$PORT -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$PID" ]]; then
    kill -9 $PID 2>/dev/null || true
    echo "Killed PID $PID on port $PORT"
  fi
fi

# Fallback
PIDS="$(pgrep -f 'node .*discovery_server.js' || true)"
if [[ -n "$PIDS" ]]; then
  kill -9 $PIDS 2>/dev/null || true
  echo "Killed PIDs: $PIDS"
fi

echo "Done."