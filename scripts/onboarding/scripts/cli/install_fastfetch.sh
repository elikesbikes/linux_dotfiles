#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_fastfetch.sh
# Version: 1.1.0
#
# Versioning:
# 1.1.0 - FIX: Script previously installed neovim due to
#         copy/paste of SCRIPT_NAME and package. Now correctly
#         installs fastfetch.
# 1.0.0 - Initial implementation.
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.1.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

mkdir -p "$LOG_DIR"

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

if command -v fastfetch >/dev/null 2>&1; then
  log "fastfetch already installed:"
  run "fastfetch --version"
  log "Nothing to do."
  exit 0
fi

log "Installing fastfetch (Ubuntu package)..."

# Install via apt
run "sudo apt-get install -y fastfetch"

if command -v fastfetch >/dev/null 2>&1; then
  log "SUCCESS: fastfetch installed:"
  run "fastfetch --version"
else
  log "FAIL: fastfetch not found after install"
  exit 1
fi

log "=================================================="
log "[$SCRIPT_NAME] Completed at: $(ts)"
log "=================================================="
