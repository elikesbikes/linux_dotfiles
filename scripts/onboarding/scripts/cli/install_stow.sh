#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_stow.sh
# Version: 1.2.0
#
# Versioning:
# 1.0.0 - Initial implementation
# 1.2.0 - Add state-based idempotency:
#         - Exit immediately if stow is already marked as installed
#         - Use XDG state marker as source of truth
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.2.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/stow"

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# State-based idempotency check (authoritative)
# --------------------------------------------------
if [[ -f "$STATE_FILE" ]]; then
  echo "STATE: stow already marked as installed ($STATE_FILE)"
  echo "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Binary presence check (defensive)
# --------------------------------------------------
if command -v stow >/dev/null 2>&1; then
  echo "stow already installed: $(command -v stow)"
  stow --version || true
  echo "Marking as installed."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Installation
# --------------------------------------------------
echo "Installing stow via apt..."

sudo apt-get update
sudo apt-get install -y stow

# --------------------------------------------------
# Post-install validation
# --------------------------------------------------
if command -v stow >/dev/null 2>&1; then
  echo "SUCCESS: stow installed: $(command -v stow)"
  stow --version || true
  touch "$STATE_FILE"
else
  echo "FAIL: stow not found after install"
  exit 1
fi

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
