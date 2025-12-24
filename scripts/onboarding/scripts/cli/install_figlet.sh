#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_figlet.sh
# Version: 1.2.0
#
# Versioning:
# 1.0.0 - Initial implementation
# 1.2.0 - Add state-based idempotency:
#         - Exit immediately if figlet is already marked as installed
#         - Use XDG state marker as source of truth
# ==================================================

SCRIPT_NAME="install_figlet.sh"
SCRIPT_VERSION="1.2.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/install_figlet.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/figlet"

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"

ts() { date +"%a %b %d %I:%M:%S %p %Z %Y"; }

log() {
  echo "$1" | tee -a "$LOG_FILE"
}

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "[DRY-RUN] $*"
  else
    eval "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

log "=================================================="
log "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
log "[$SCRIPT_NAME] Starting at: $(ts)"
log "Log: $LOG_FILE"
log "=================================================="

# --------------------------------------------------
# State-based idempotency check (authoritative)
# --------------------------------------------------
if [[ -f "$STATE_FILE" ]]; then
  log "STATE: figlet already marked as installed ($STATE_FILE)"
  log "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Binary presence check (defensive)
# --------------------------------------------------
if command -v figlet >/dev/null 2>&1; then
  log "figlet already installed: $(command -v figlet)"
  run "figlet -v || true"
  log "Marking as installed."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Installation
# --------------------------------------------------
log "Installing figlet via apt..."

# NOTE: Intentionally NOT running apt update here
run "sudo apt-get install -y figlet"

# --------------------------------------------------
# Post-install validation
# --------------------------------------------------
if command -v figlet >/dev/null 2>&1; then
  log "SUCCESS: figlet installed: $(command -v figlet)"
  run "figlet -v || true"
  touch "$STATE_FILE"
else
  log "FAIL: figlet not found after install"
  exit 1
fi

log "=================================================="
log "[$SCRIPT_NAME] Completed at: $(ts)"
log "=================================================="
