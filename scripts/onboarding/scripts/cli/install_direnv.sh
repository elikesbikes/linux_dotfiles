#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_direnv.sh
# Version: 1.1.0
#
# 1.0.0 - Initial implementation
# 1.1.0 - If direnv is already installed, exit immediately
#         without running apt update or install
# ==================================================

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/direnv"

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Version: 1.1.0"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Early exit: already installed
# --------------------------------------------------
if command -v direnv >/dev/null 2>&1; then
  echo "direnv already installed: $(command -v direnv)"
  direnv version || true
  echo "No action required. Exiting."
  exit 0
fi

# --------------------------------------------------
# Install direnv
# --------------------------------------------------
echo "Installing direnv via apt..."
sudo apt-get update
sudo apt-get install -y direnv

# --------------------------------------------------
# Post-install verification + state marker
# --------------------------------------------------
if command -v direnv >/dev/null 2>&1; then
  touch "$STATE_FILE"
  echo "Installed: $(command -v direnv)"
  direnv version || true
  echo "State marker written: $STATE_FILE"
else
  echo "ERROR: direnv installation failed"
  exit 1
fi

echo "Done."
