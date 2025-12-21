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

if command -v zoxide >/dev/null 2>&1; then
  echo "zoxide already installed: $(command -v zoxide)"
  zoxide --version || true
  echo "Upgrading via apt (safe)..."
  sudo apt-get update
  sudo apt-get install -y zoxide
  echo "Done."
  exit 0
fi

echo "Installing zoxide via apt..."
sudo apt-get update
sudo apt-get install -y zoxide

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

echo "Installed: $(command -v zoxide)"
zoxide --version || true
echo "Done."