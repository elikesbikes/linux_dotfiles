#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_build-essential.sh
# Version: 1.0.0
#
# Versioning:
# 1.0.0 - Initial implementation:
#         - State-based idempotency via XDG state marker
#         - Install build-essential (gcc, g++, make, libc-dev) via apt
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/build-essential"

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
  echo "STATE: build-essential already marked as installed ($STATE_FILE)"
  echo "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Package presence check (defensive)
# --------------------------------------------------
if dpkg -s build-essential >/dev/null 2>&1; then
  echo "build-essential already installed."
  gcc --version | head -n 1 || true
  echo "Marking as installed."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Installation
# --------------------------------------------------
echo "Installing build-essential via apt..."

# Per rule 3: non-core categories assume the apt cache is already fresh.
sudo apt-get install -y build-essential

# --------------------------------------------------
# Post-install validation
# --------------------------------------------------
if dpkg -s build-essential >/dev/null 2>&1; then
  echo "SUCCESS: build-essential installed."
  gcc --version | head -n 1 || true
  touch "$STATE_FILE"
else
  echo "FAIL: build-essential not found after install"
  exit 1
fi

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
