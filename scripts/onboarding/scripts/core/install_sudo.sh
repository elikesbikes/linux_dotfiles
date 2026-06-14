#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_sudo.sh
# Version: 1.0.0
#
# Versioning:
# 1.0.0 - Initial implementation:
#         - State-based idempotency via XDG state marker
#         - Ensure sudo is installed via apt
#         - Report sudo version details (sudo -V)
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/sudo"

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

report_version() {
  echo ""
  echo "sudo version details:"
  sudo -V | head -n 6 || true
}

# --------------------------------------------------
# State-based idempotency check (authoritative)
# --------------------------------------------------
if [[ -f "$STATE_FILE" ]]; then
  echo "STATE: sudo already marked as installed ($STATE_FILE)"
  report_version
  echo "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Binary presence check (defensive)
# --------------------------------------------------
if command -v sudo >/dev/null 2>&1; then
  echo "sudo already installed: $(command -v sudo)"
  report_version
  echo "Marking as installed."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Installation
# --------------------------------------------------
echo "Installing sudo via apt..."

# sudo may not exist yet; fall back to running apt directly as needed.
if command -v sudo >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y sudo
else
  apt-get update
  apt-get install -y sudo
fi

# --------------------------------------------------
# Post-install validation
# --------------------------------------------------
if command -v sudo >/dev/null 2>&1; then
  echo "SUCCESS: sudo installed: $(command -v sudo)"
  report_version
  touch "$STATE_FILE"
else
  echo "FAIL: sudo not found after install"
  exit 1
fi

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
