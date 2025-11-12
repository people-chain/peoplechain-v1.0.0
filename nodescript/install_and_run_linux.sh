#!/usr/bin/env bash
set -euo pipefail

PORT=8080
NAME="peoplechain-discovery"
SERVICE_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE_USER="$SERVICE_USER_DIR/${NAME}.service"
SERVICE_FILE_SYS="/etc/systemd/system/${NAME}.service"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"; shift 2 ;;
    *)
      echo "Unknown arg: $1" >&2; exit 1 ;;
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
  echo "Node.js not found in PATH. Please install Node.js." >&2
  exit 1
fi

echo "Using node: $NODE_BIN"
echo "Server: $SERVER_JS"

start_systemd_user() {
  mkdir -p "$SERVICE_USER_DIR"
  cat > "$SERVICE_FILE_USER" <<EOF
[Unit]
Description=PeopleChain Discovery Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$NODE_BIN $SERVER_JS --port $PORT
Restart=always
RestartSec=2
Environment=PORT=$PORT

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$NAME.service"
}

start_systemd_root() {
  sudo bash -c "cat > '$SERVICE_FILE_SYS'" <<EOF
[Unit]
Description=PeopleChain Discovery Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$NODE_BIN $SERVER_JS --port $PORT
Restart=always
RestartSec=2
Environment=PORT=$PORT

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now "$NAME.service"
}

fallback_nohup() {
  LOG="$SCRIPT_DIR/${NAME}.log"
  echo "Starting with nohup (no systemd detected). Logs: $LOG"
  nohup "$NODE_BIN" "$SERVER_JS" --port "$PORT" >"$LOG" 2>&1 &
}

if command -v systemctl >/dev/null 2>&1; then
  # Try user service first
  if systemctl --user status >/dev/null 2>&1; then
    start_systemd_user
  else
    echo "systemd user instance not detected; falling back to system-level service (requires sudo)."
    start_systemd_root
  fi
else
  fallback_nohup
fi

echo "Discovery server starting on port $PORT"
URL="http://127.0.0.1:$PORT/"
echo "Open: $URL"
if command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL" >/dev/null 2>&1 & fi