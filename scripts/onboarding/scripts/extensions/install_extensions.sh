#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/install_extensions.log"
mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[extensions] GNOME Extensions Reconciliation"
echo "=================================================="
echo "Date: $(date)"
echo "Log : $LOG_FILE"
echo

# --------------------------------------------------
# Preconditions
# --------------------------------------------------

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "GNOME not detected (gnome-extensions missing)."
  echo "Skipping extensions."
  exit 0
fi

GNOME_VERSION="$(gnome-shell --version | awk '{print $3}')"
echo "Detected GNOME Shell : $GNOME_VERSION"
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/extensions.conf"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: extensions.conf not found."
  exit 1
fi

# --------------------------------------------------
# Helpers
# --------------------------------------------------

is_installed() {
  gnome-extensions info "$1" >/dev/null 2>&1
}

is_enabled() {
  gnome-extensions info "$1" 2>/dev/null | grep -q "State: ENABLED"
}

is_disabled() {
  gnome-extensions info "$1" 2>/dev/null | grep -q "State: DISABLED"
}

has_tty() {
  [[ -e /dev/tty ]]
}

prompt_manual_install() {
  local uuid="$1"
  local url="https://extensions.gnome.org"

  echo "  action : manual install required"
  echo "  source : $url"

  if ! has_tty; then
    echo "  note   : no TTY available, skipping prompt"
    return
  fi

  if command -v gum >/dev/null 2>&1; then
    if gum confirm "Install GNOME extension '$uuid' manually now?" </dev/tty; then
      xdg-open "$url" >/dev/tty 2>/dev/null || true
      echo "  note   : waiting briefly for manual install"
      sleep 5
    else
      echo "  note   : user skipped manual install"
    fi
  else
    read -rp "Install '$uuid' manually now? [y/N]: " ans </dev/tty
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      xdg-open "$url" >/dev/tty 2>/dev/null || true
      read -rp "Press Enter once installation is complete..." </dev/tty
    else
      echo "  note   : user skipped manual install"
    fi
  fi
}

# --------------------------------------------------
# Reconcile extensions
# --------------------------------------------------

echo "--------------------------------------------------"
echo " Reconciling extensions state"
echo "--------------------------------------------------"
echo

while IFS='=' read -r UUID DESIRED; do
  [[ -z "$UUID" || "$UUID" =~ ^# ]] && continue

  DESIRED="$(echo "$DESIRED" | tr '[:upper:]' '[:lower:]')"

  echo "→ $UUID"
  echo "  desired: $DESIRED"

  if ! is_installed "$UUID"; then
    echo "  status : missing"
    prompt_manual_install "$UUID"
    echo
    continue
  fi

  echo "  status : installed"

  if [[ "$DESIRED" == "enabled" ]]; then
    if is_enabled "$UUID"; then
      echo "  state  : already enabled"
      echo "  action : none"
    else
      echo "  state  : disabled"
      echo "  action : enabling"
      gnome-extensions enable "$UUID" || echo "  WARN   : enable failed"
    fi
  else
    if is_disabled "$UUID"; then
      echo "  state  : already disabled"
      echo "  action : none"
    else
      echo "  state  : enabled"
      echo "  action : disabling"
      gnome-extensions disable "$UUID" || echo "  WARN   : disable failed"
    fi
  fi

  echo
done < "$CONF_FILE"

echo "=================================================="
echo " Extensions reconciliation COMPLETE"
echo "=================================================="
echo "Log out and back in if changes do not apply."
