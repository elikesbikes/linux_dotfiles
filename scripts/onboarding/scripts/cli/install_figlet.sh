#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="install_figlet.sh"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/install_figlet.log"

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

if command -v figlet >/dev/null 2>&1; then
  log "figlet already installed: $(command -v figlet)"
  run "figlet -v || true"
  log "Nothing to do."
  exit 0
fi

log "Installing figlet via apt..."

# NOTE: We intentionally do NOT run `apt update` here if you want core-only updates.
# If you still want updates per-script, uncomment the next line.
# run "sudo apt-get update"

run "sudo apt-get install -y figlet"

if command -v figlet >/dev/null 2>&1; then
  log "SUCCESS: figlet installed: $(command -v figlet)"
  run "figlet -v || true"
else
  log "FAIL: figlet not found after install"
  exit 1
fi
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

log "=================================================="
log "[$SCRIPT_NAME] Completed at: $(ts)"
log "=================================================="
