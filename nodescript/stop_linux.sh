#!/usr/bin/env bash
set -euo pipefail

PORT=8080
NAME="peoplechain-discovery"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

echo "Stopping discovery server (port $PORT)..."

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user stop "$NAME.service" 2>/dev/null || true
  sudo systemctl stop "$NAME.service" 2>/dev/null || true
fi

# Kill process by port
if command -v lsof >/dev/null 2>&1; then
  PID="$(lsof -t -i :$PORT -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$PID" ]]; then
    kill -9 $PID 2>/dev/null || true
    echo "Killed PID $PID on port $PORT"
  fi
fi

# Fallback: kill node processes running discovery_server.js
PIDS="$(pgrep -f 'node .*discovery_server.js' || true)"
if [[ -n "$PIDS" ]]; then
  kill -9 $PIDS 2>/dev/null || true
  echo "Killed PIDs: $PIDS"
fi

echo "Done."