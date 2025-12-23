#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# GNOME Extensions – Auto Reconcile (Ubuntu)
# ==================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/extensions.conf"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_DIR/logs"
LOG_FILE="$LOG_DIR/install_extensions.log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[extensions] GNOME Extensions Reconciliation"
echo "=================================================="
echo "Date : $(date)"
echo "Log  : $LOG_FILE"
echo

# --------------------------------------------------
# Preconditions
# --------------------------------------------------

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "GNOME not detected (gnome-extensions missing)."
  echo "Skipping extensions step."
  exit 0
fi

GNOME_VERSION="$(gnome-shell --version | awk '{print $3}')"
GNOME_MAJOR="${GNOME_VERSION%%.*}"

echo "Detected GNOME Shell : $GNOME_VERSION"
echo

# --------------------------------------------------
# Ubuntu deps (system extensions only)
# --------------------------------------------------

if command -v apt >/dev/null 2>&1; then
  echo "Ensuring system GNOME extensions package (Ubuntu)..."
  sudo apt-get update -y
  sudo apt-get install -y gnome-shell-extensions curl jq unzip
  echo
fi

# --------------------------------------------------
# Helpers
# --------------------------------------------------

is_installed() {
  gnome-extensions list | grep -qx "$1"
}

is_enabled() {
  gnome-extensions list --enabled | grep -qx "$1"
}

manual_required=()

# --------------------------------------------------
# Main loop
# --------------------------------------------------

echo "Processing extensions.conf..."
echo

while IFS="=" read -r EXT_ID DESIRED_STATE; do
  [[ -z "$EXT_ID" || "$EXT_ID" =~ ^# ]] && continue

  echo "→ $EXT_ID"
  echo "  desired : $DESIRED_STATE"

  if is_installed "$EXT_ID"; then
    echo "  status  : installed"

    if [[ "$DESIRED_STATE" == "enabled" ]]; then
      if is_enabled "$EXT_ID"; then
        echo "  state   : already enabled"
        echo "  action  : none"
      else
        echo "  state   : disabled"
        echo "  action  : enabling"
        gnome-extensions enable "$EXT_ID" || true
      fi
    else
      if is_enabled "$EXT_ID"; then
        echo "  state   : enabled"
        echo "  action  : disabling"
        gnome-extensions disable "$EXT_ID" || true
      else
        echo "  state   : already disabled"
        echo "  action  : none"
      fi
    fi

  else
    echo "  status  : not installed"
    echo "  note    : third-party GNOME extension"
    echo "  source  : https://extensions.gnome.org"
    echo "  action  : manual install required"
    manual_required+=("$EXT_ID")
  fi

  echo
done < "$CONF_FILE"

# --------------------------------------------------
# Summary
# --------------------------------------------------

echo "=================================================="
echo "Extensions reconciliation COMPLETE"
echo "=================================================="

if (( ${#manual_required[@]} > 0 )); then
  echo
  echo "Manual installation required for the following extensions:"
  echo

  for ext in "${manual_required[@]}"; do
    echo "  • $ext"
  done

  echo
  echo "Reason:"
  echo "  These are third-party GNOME extensions."
  echo "  Ubuntu GNOME $GNOME_MAJOR does not support"
  echo "  reliable unattended installation for them."
  echo
  echo "Next step:"
  echo "  1. Install them from https://extensions.gnome.org"
  echo "  2. Re-run: onboarding → Install → Extensions"
fi

echo
echo "If extensions do not activate immediately,"
echo "log out and log back in."
echo
