#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

echo "Standardized source exception: yazi is installed via SNAP (per your rule)."

echo "Ensuring snap is present..."
sudo apt-get update
sudo apt-get install -y snapd

if snap list 2>/dev/null | awk '{print $1}' | grep -qx "yazi"; then
  echo "yazi already installed via snap. Refreshing..."
  sudo snap refresh yazi
else
  echo "Installing yazi via snap..."
  # Some snaps require --classic; if it fails, we retry without it.
  if ! sudo snap install yazi --classic; then
    echo "Install with --classic failed. Retrying without --classic..."
    sudo snap install yazi
  fi
fi

echo "yazi location:"
command -v yazi || true

echo "yazi snap info:"
snap info yazi | sed -n '1,40p' || true
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

echo "Done."

