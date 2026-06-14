#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_default_editor.sh
# Version: 1.0.0
#
# Versioning:
# 1.0.0 - Initial implementation:
#         - Sets the SYSTEM default editor to nvim via the Debian
#           `editor` alternative (/usr/bin/editor), which sensible-editor,
#           `crontab -e`, etc. fall back to. Fresh Debian/Ubuntu defaults to
#           nano; this pins nvim to match the TARS baseline.
#         - State-based idempotency via XDG state marker.
#
# Scope note: this manages the /etc-level `editor` alternative (system admin
# config, like the sudo alternative) — NOT a user dotfile. EDITOR/VISUAL env
# vars stay in shell dotfiles. Requires nvim (cli/install_neovim.sh).
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/default-editor"

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Helpers
# --------------------------------------------------
as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

current_editor() {
  update-alternatives --query editor 2>/dev/null | awk -F': ' '/^Value:/{print $2}'
}

# --------------------------------------------------
# State-based idempotency check (authoritative)
# --------------------------------------------------
if [[ -f "$STATE_FILE" ]]; then
  echo "STATE: default editor already configured ($STATE_FILE)"
  echo "Current editor alternative: $(current_editor)"
  echo "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Prerequisite: nvim must be installed
# --------------------------------------------------
NVIM="$(command -v nvim || true)"
if [[ -z "$NVIM" ]]; then
  echo "FAIL: nvim not found. Run cli/install_neovim.sh first."
  exit 1
fi
echo "Using nvim: $NVIM"

if ! command -v update-alternatives >/dev/null 2>&1; then
  echo "FAIL: update-alternatives not available."
  exit 1
fi

# --------------------------------------------------
# Register nvim as an editor alternative if missing, then select it
# --------------------------------------------------
if ! update-alternatives --list editor 2>/dev/null | grep -qx "$NVIM"; then
  echo "Registering $NVIM as an 'editor' alternative..."
  as_root update-alternatives --install /usr/bin/editor editor "$NVIM" 100
fi

echo "Setting system default editor to nvim..."
as_root update-alternatives --set editor "$NVIM"

# --------------------------------------------------
# Post-config validation
# --------------------------------------------------
if [[ "$(current_editor)" == "$NVIM" ]]; then
  echo "SUCCESS: default editor is now nvim ($(current_editor))"
  touch "$STATE_FILE"
else
  echo "FAIL: editor alternative is '$(current_editor)', expected '$NVIM'."
  echo "Inspect: update-alternatives --display editor"
  exit 1
fi

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
