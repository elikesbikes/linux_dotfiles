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

if command -v exa >/dev/null 2>&1; then
  echo "exa already installed: $(command -v exa)"
  exa --version || true
  echo "Done."
  exit 0
fi

echo "Installing exa via apt..."
sudo apt-get update
if sudo apt-get install -y exa; then
  echo "exa installed successfully."
  exa --version || true
  echo "Done."
  exit 0
fi

echo "WARNING: 'exa' package install failed. Falling back to 'eza' (modern replacement)."
sudo apt-get install -y eza

if command -v eza >/dev/null 2>&1; then
  echo "eza installed: $(command -v eza)"
  eza --version || true
  echo "NOTE: eza is installed instead of exa."
else
  echo "ERROR: Failed to install both exa and eza."
  exit 1
fi
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

echo "Done."
