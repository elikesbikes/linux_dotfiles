#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/install_extensions.log"
mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[extensions] Auto-install + Reconcile (SAFE MODE)"
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
GNOME_MAJOR="${GNOME_VERSION%%.*}"

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

interactive() {
  [[ -t 0 ]]
}

manual_prompt() {
  local uuid="$1"
  local url="https://extensions.gnome.org"

  if ! interactive; then
    echo "  note   : non-interactive session, skipping manual install"
    return
  fi

  if command -v gum >/dev/null 2>&1; then
    if gum confirm "Manual install required for $uuid. Open extensions.gnome.org?"; then
      xdg-open "$url" >/dev/null 2>&1 || true
    else
      echo "  note   : user skipped manual install"
    fi
  else
    echo
    read -rp "Manual install required for $uuid. Open extensions.gnome.org? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      xdg-open "$url" >/dev/null 2>&1 || true
    else
      echo "  note   : user skipped manual install"
    fi
  fi
}

# --------------------------------------------------
# Reconciliation loop
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
    echo "  action : manual install required"
    manual_prompt "$UUID"
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
echo "If changes do not apply immediately, log out and log back in."
