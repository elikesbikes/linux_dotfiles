#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"

mkdir -p "$LOG_DIR" "$STATE_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Installing Desktop Snap Apps"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Ensure snapd
# --------------------------------------------------
if ! command -v snap >/dev/null 2>&1; then
  echo "Installing snapd..."
  sudo apt-get update
  sudo apt-get install -y snapd
fi

echo ""
echo "Installing snap desktop applications..."

SNAP_APPS=(
  brave
  spotify
  todoist
  rustdesk
  protonplus
)

for app in "${SNAP_APPS[@]}"; do
  if snap list | awk '{print $1}' | grep -qx "$app"; then
    echo "✔ $app already installed"
  else
    echo "➕ Installing $app..."
    sudo snap install "$app"
  fi
done

touch "$STATE_DIR/desktop_snap"

echo "  "
echo "=================================================="
echo " Desktop Snap Apps Installation Complete"
echo "=================================================="
