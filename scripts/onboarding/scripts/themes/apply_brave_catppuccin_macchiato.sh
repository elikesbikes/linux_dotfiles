#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# apply_brave_catppuccin_macchiato.sh
#
# Purpose:
#   Apply a Catppuccin Macchiato-inspired color palette to Brave
#   by updating the user profile Preferences JSON.
#
#   - HOME directory only
#   - No /etc usage
#   - No system policies
#   - No automatic package installs
#
# How it works:
#   - Locates the Brave Default profile Preferences file
#   - Creates a timestamped backup
#   - Uses jq to patch theme.color_palette only
#   - Verifies the expected color was written
#
# Versioning:
#   Version: 1.0.0
#   Status : experimental
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
err()  { echo "ERROR: $*" >&2; }
info() { echo "INFO : $*"; }

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required command not found: $cmd"
    err "Install it manually and re-run (no auto-installs here)."
    exit 1
  fi
}

is_brave_running() {
  pgrep -f brave-browser >/dev/null 2>&1
}

backup_preferences() {
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local backup_file="$BACKUP_DIR/Preferences.${PROFILE_NAME}.${ts}.bak"
  cp -a "$PREFS_FILE" "$backup_file"
  info "Backup created: $backup_file"
}

apply_macchiato_palette() {
  local tmp
  tmp="$(mktemp)"

  # Catppuccin Macchiato palette (Brave-compatible)
  # Base      : #24273a
  # Mantle    : #1e2030
  # Surface0  : #363a4f
  # Text      : #cad3f5
  # Accent    : #8aadf4
  jq '
    .theme = (
      (.theme // {}) |
      .color_palette = {
        "frame": "#24273a",
        "frame_inactive": "#1e2030",
        "toolbar": "#24273a",
        "tab_text": "#cad3f5",
        "tab_background_text": "#cad3f5",
        "bookmark_text": "#cad3f5",
        "ntp_background": "#24273a",
        "ntp_text": "#cad3f5",
        "button_background": "#363a4f"
      }
    )
  ' "$PREFS_FILE" > "$tmp"

  mv "$tmp" "$PREFS_FILE"
  info "Catppuccin Macchiato palette applied"
}

verify_theme() {
  if jq -e '.theme.color_palette.frame == "#24273a"' "$PREFS_FILE" >/dev/null; then
    info "Verification successful: Macchiato palette detected"
  else
    err "Verification failed: expected palette not found"
    exit 1
  fi
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
need_cmd jq
need_cmd pgrep
need_cmd cp
need_cmd mv
need_cmd date

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

info "Profile     : $PROFILE_NAME"
info "Preferences : $PREFS_FILE"

backup_preferences
apply_macchiato_palette
verify_theme

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date -Is)"
echo "Start Brave to see the theme applied."
echo "=================================================="
