#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="install_neovim.sh"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/install_neovim.log"

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
log "[$SCRIPT_NAME] Starting at: $(ts)"
log "Log: $LOG_FILE"
log "=================================================="

if command -v nvim >/dev/null 2>&1; then
  log "Neovim already installed:"
  run "nvim --version | head -n 2"
  log "Nothing to do."
  exit 0
fi

log "Installing Neovim (Ubuntu package)..."

# Install via apt
run "sudo apt-get install -y neovim"

if command -v nvim >/dev/null 2>&1; then
  log "SUCCESS: Neovim installed:"
  run "nvim --version | head -n 2"
else
  log "FAIL: Neovim not found after install"
  exit 1
fi
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"
log "=================================================="
log "[$SCRIPT_NAME] Completed at: $(ts)"
log "=================================================="
