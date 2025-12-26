#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# apply_brave_catppuccin_mocha.sh
#
# Purpose:
#   Apply a Catppuccin Mocha-inspired color palette to Brave by
#   updating the user profile Preferences JSON.
#
#   - HOME directory only
#   - No /etc usage
#   - No sudo installs
#   - Suitable for dotfiles + onboarding workflows
#
# How it works:
#   Brave stores per-profile UI settings in:
#     ~/.config/BraveSoftware/Brave-Browser/<profile>/Preferences
#
#   This script patches the `theme.color_palette` keys using jq.
#
# Versioning:
#   Version: 1.0.0
#   Status : experimental (not yet frozen / production)
# ============================================================

SCRIPT_NAME="$(basename "$0")"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/backups/brave"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

echo "=================================================="
echo "[$SCRIPT_NAME] Starting at: $(date -Is)"
echo "Version: 1.0.0"
echo "Log: $LOG_FILE"
echo "=================================================="

# ------------------------------------------------------------
# Configuration (HOME only)
# ------------------------------------------------------------
BRAVE_CONFIG_DIR="$HOME/.config/BraveSoftware/Brave-Browser"
PROFILE_NAME="Default"
PROFILE_DIR="$BRAVE_CONFIG_DIR/$PROFILE_NAME"
PREFS_FILE="$PROFILE_DIR/Preferences"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
err() { echo "ERROR: $*" >&2; }
info() { echo "INFO : $*"; }

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required command not found: $cmd"
    err "Install it manually and re-run (this script never installs packages)."
    exit 1
  fi
}

is_brave_running() {
  pgrep -f "brave-browser" >/dev/null 2>&1
}

backup_preferences() {
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local backup_file="$BACKUP_DIR/Preferences.${PROFILE_NAME}.${ts}.bak"
  cp -a "$PREFS_FILE" "$backup_file"
  info "Backup created: $backup_file"
}

apply_catppuccin_mocha() {
  local tmp
  tmp="$(mktemp)"

  # Catppuccin Mocha palette (approximate, Brave-compatible)
  # Base      : #1e1e2e
  # Mantle    : #181825
  # Surface0  : #313244
  # Text      : #cdd6f4
  # Accent    : #89b4fa
  jq '
    .theme = (
      (.theme // {}) |
      .color_palette = {
        "frame": "#1e1e2e",
        "frame_inactive": "#181825",
        "toolbar": "#1e1e2e",
        "tab_text": "#cdd6f4",
        "tab_background_text": "#cdd6f4",
        "bookmark_text": "#cdd6f4",
        "ntp_background": "#1e1e2e",
        "ntp_text": "#cdd6f4",
        "button_background": "#313244"
      }
    )
  ' "$PREFS_FILE" >"$tmp"

  mv "$tmp" "$PREFS_FILE"
  info "Catppuccin Mocha palette applied"
}

verify_theme() {
  if jq -e '.theme.color_palette.frame == "#1e1e2e"' "$PREFS_FILE" >/dev/null; then
    info "Verification successful: Mocha palette detected"
  else
    err "Verification failed: expected palette not found"
    exit 1
  fi
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
need_cmd jq
need_cmd cp
need_cmd mv
need_cmd date
need_cmd pgrep

if [[ ! -d "$PROFILE_DIR" ]]; then
  err "Brave profile not found: $PROFILE_DIR"
  err "Launch Brave once to initialize the profile, then re-run."
  exit 1
fi

if [[ ! -f "$PREFS_FILE" ]]; then
  err "Preferences file not found: $PREFS_FILE"
  exit 1
fi

if is_brave_running; then
  err "Brave is currently running."
  err "Close Brave completely before running this script."
  err "Tip: pkill -f brave"
  exit 1
fi

info "Profile      : $PROFILE_NAME"
info "Preferences  : $PREFS_FILE"

backup_preferences
apply_catppuccin_mocha
verify_theme

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date -Is)"
echo "Start Brave to see the theme applied."
echo "=================================================="
