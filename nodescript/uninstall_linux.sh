#!/usr/bin/env bash
set -euo pipefail

PORT=8080
NAME="peoplechain-discovery"
SERVICE_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE_USER="$SERVICE_USER_DIR/${NAME}.service"
SERVICE_FILE_SYS="/etc/systemd/system/${NAME}.service"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

"$(dirname "$0")/stop_linux.sh" --port "$PORT" || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable "$NAME.service" 2>/dev/null || true
  systemctl --user stop "$NAME.service" 2>/dev/null || true
  if [[ -f "$SERVICE_FILE_USER" ]]; then
    rm -f "$SERVICE_FILE_USER"
    systemctl --user daemon-reload || true
    echo "Removed user service file."
  fi
  sudo systemctl disable "$NAME.service" 2>/dev/null || true
  sudo systemctl stop "$NAME.service" 2>/dev/null || true
  if [[ -f "$SERVICE_FILE_SYS" ]]; then
    sudo rm -f "$SERVICE_FILE_SYS"
    sudo systemctl daemon-reload || true
    echo "Removed system service file."
  fi
fi

echo "Uninstall complete."