#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Script: install_yazi.sh
#
# Purpose:
#   Install and manage yazi using SNAP only.
#   This script enforces a standardized source exception where yazi is
#   intentionally installed via snap.
#
# Versioning:
#   1.0.0 - Initial implementation (snap-based install, unversioned)
#   1.2.0 - Proper semantic versioning, idempotent snap handling,
#           improved logging, and stable state tracking
#
# Author:
#   Tars (ELIKESBIKES)
###############################################################################

SCRIPT_VERSION="1.2.0"
SCRIPT_NAME="$(basename "$0")"

# Logging
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# State tracking
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_MARKER="$STATE_DIR/cli_yazi"
mkdir -p "$STATE_DIR"

echo "=================================================="
echo "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
echo "Started at: $(date)"
echo "Log file : $LOG_FILE"
echo "=================================================="

echo "Source policy:"
echo "  - yazi is intentionally installed via SNAP (approved exception)"

###############################################################################
# Ensure snap is available
###############################################################################
echo "Checking for snapd..."

if ! command -v snap >/dev/null 2>&1; then
  echo "snapd not found. Installing snapd..."
  sudo apt-get update
  sudo apt-get install -y snapd
else
  echo "snapd already present."
fi

###############################################################################
# Install or refresh yazi
###############################################################################
if snap list 2>/dev/null | awk '{print $1}' | grep -qx "yazi"; then
  echo "yazi already installed via snap."
  echo "Refreshing yazi to latest revision..."
  sudo snap refresh yazi
else
  echo "Installing yazi via snap..."
  if ! sudo snap install yazi --classic; then
    echo "Install with --classic failed. Retrying without --classic..."
    sudo snap install yazi
  fi
fi

###############################################################################
# Verification
###############################################################################
echo "Verifying yazi installation..."

if command -v yazi >/dev/null 2>&1; then
  echo "✔ yazi is available at: $(command -v yazi)"
else
  echo "✘ yazi command not found after installation"
  exit 1
fi

echo "yazi snap info (summary):"
snap info yazi | sed -n '1,40p' || true

###############################################################################
# State marker
###############################################################################
touch "$STATE_MARKER"
echo "State marker written to: $STATE_MARKER"

echo "=================================================="
echo "[$SCRIPT_NAME] Completed successfully at: $(date)"
echo "=================================================="
