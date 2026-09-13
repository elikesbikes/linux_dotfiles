#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_fastfetch.sh
# Version: 2.0.0
#
# Versioning:
# 2.0.0 - Install latest fastfetch from GitHub releases instead of Ubuntu
#         repo (repo version lacks kitty graphics auto-detection).
#         Also installs imagemagick (required for image logo rendering).
# 1.1.0 - FIX: Script previously installed neovim due to
#         copy/paste of SCRIPT_NAME and package. Now correctly
#         installs fastfetch.
# 1.0.0 - Initial implementation.
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="2.0.0"

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

# --------------------------------------------------
# ImageMagick (required for fastfetch image logo rendering)
# --------------------------------------------------
if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  log "Installing imagemagick (needed for fastfetch image logos)..."
  run "sudo apt-get install -y imagemagick"
else
  log "ImageMagick already installed."
fi

# --------------------------------------------------
# Fastfetch — latest from GitHub releases
# --------------------------------------------------
LATEST_DEB="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
TMP_DEB="/tmp/fastfetch-latest.deb"

if command -v fastfetch >/dev/null 2>&1; then
  CURRENT="$(fastfetch --version | awk '{print $2}')"
  log "fastfetch $CURRENT is installed — checking for update..."
else
  CURRENT=""
  log "fastfetch not found — installing..."
fi

log "Downloading latest fastfetch from GitHub..."
run "curl -sL '$LATEST_DEB' -o '$TMP_DEB'"

log "Installing fastfetch .deb..."
run "sudo dpkg -i '$TMP_DEB'"
rm -f "$TMP_DEB"

if command -v fastfetch >/dev/null 2>&1; then
  NEW="$(fastfetch --version | awk '{print $2}')"
  if [[ -n "$CURRENT" && "$CURRENT" == "$NEW" ]]; then
    log "SUCCESS: fastfetch $NEW (already up to date)"
  else
    log "SUCCESS: fastfetch installed: $NEW"
  fi
else
  log "FAIL: fastfetch not found after install"
  exit 1
fi

log "=================================================="
log "[$SCRIPT_NAME] Completed at: $(ts)"
log "=================================================="
