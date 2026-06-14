#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_exa.sh
# Version: 1.2.0
#
# Versioning:
# 1.0.0 - Initial implementation (exa with eza fallback)
# 1.2.0 - FIX: State markers were dead code (placed after exit 0)
#         and used the literal "<category>" placeholder.
#         - Add state-based idempotency early exit
#         - Write a real "exa" state marker on every success path
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.2.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/exa"

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
  echo "STATE: exa/eza already marked as installed ($STATE_FILE)"
  echo "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Binary presence check (defensive)
# --------------------------------------------------
if command -v exa >/dev/null 2>&1; then
  echo "exa already installed: $(command -v exa)"
  exa --version || true
  touch "$STATE_FILE"
  echo "Done."
  exit 0
fi

if command -v eza >/dev/null 2>&1; then
  echo "eza already installed: $(command -v eza)"
  eza --version || true
  touch "$STATE_FILE"
  echo "Done."
  exit 0
fi

# --------------------------------------------------
# Installation (exa, with eza fallback)
# --------------------------------------------------
echo "Installing exa via apt..."
sudo apt-get update
if sudo apt-get install -y exa; then
  echo "exa installed successfully."
  exa --version || true
  touch "$STATE_FILE"
  echo "Done."
  exit 0
fi

echo "WARNING: 'exa' package install failed. Falling back to 'eza' (modern replacement)."
sudo apt-get install -y eza

if command -v eza >/dev/null 2>&1; then
  echo "eza installed: $(command -v eza)"
  eza --version || true
  echo "NOTE: eza is installed instead of exa."
  touch "$STATE_FILE"
else
  echo "ERROR: Failed to install both exa and eza."
  exit 1
fi

echo "Done."
