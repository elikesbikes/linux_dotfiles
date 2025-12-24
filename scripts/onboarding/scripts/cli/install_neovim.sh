#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_neovim.sh
# Version: 1.2.0
#
# Versioning:
# 1.0.0 - Initial implementation
# 1.2.0 - Add state-based idempotency:
#         - Exit immediately if Neovim is already marked as installed
#         - Use XDG state marker as source of truth
# ==================================================

SCRIPT_NAME="install_neovim.sh"
SCRIPT_VERSION="1.2.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/install_neovim.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/neovim"

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
  log "STATE: Neovim already marked as installed ($STATE_FILE)"
  log "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Binary presence check (defensive)
# --------------------------------------------------
if command -v nvim >/dev/null 2>&1; then
  log "Neovim already installed:"
  run "nvim --version | head -n 2"
  log "Marking as installed."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Installation
# --------------------------------------------------
log "Installing Neovim via Ubuntu package (Omakub-style)..."

# Core should already have run apt update
run "sudo apt-get install -y neovim"

# --------------------------------------------------
# Post-install validation
# --------------------------------------------------
if command -v nvim >/dev/null 2>&1; then
  log "SUCCESS: Neovim installed:"
  run "nvim --version | head -n 2"
else
  log "FAIL: Neovim not found after install"
  exit 1
fi

# --------------------------------------------------
# Cleanup: remove tree-sitter-cli
# --------------------------------------------------
log "Removing tree-sitter-cli (if present)..."

if dpkg -s tree-sitter-cli >/dev/null 2>&1; then
  run "sudo apt-get remove -y tree-sitter-cli"
  run "sudo apt-get autoremove -y"
  log "tree-sitter-cli removed."
else
  log "tree-sitter-cli not installed. Nothing to remove."
fi

# --------------------------------------------------
# Mark completion
# --------------------------------------------------
touch "$STATE_FILE"

log "=================================================="
log "[$SCRIPT_NAME] Completed at: $(ts)"
log "=================================================="
