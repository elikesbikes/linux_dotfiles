#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Ensuring OpenSSH client"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

if command -v ssh >/dev/null 2>&1; then
  echo "OpenSSH already installed:"
  ssh -V
else
  echo "Installing OpenSSH client..."
  sudo apt-get update
  sudo apt-get install -y openssh-client
fi
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

echo ""
echo "=================================================="
echo " SSH core setup complete"
echo "=================================================="
