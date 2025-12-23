#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# GNOME Extensions Installer (Interactive & Safe)
# ==================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/extensions.conf"

clear
echo "=================================================="
echo " GNOME Extensions Installer"
echo "=================================================="
echo

# --------------------------------------------------
# Preconditions
# --------------------------------------------------

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "GNOME Shell not detected."
  echo "This system does not support GNOME extensions."
  echo
  read -rp "Press Enter to return to menu..."
  exit 0
fi

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: extensions.conf not found:"
  echo "  $CONF_FILE"
  echo
  read -rp "Press Enter to return to menu..."
  exit 1
fi

echo "Detected GNOME Shell:"
gnome-shell --version
echo

echo "This script will:"
echo " • Install missing extensions"
echo " • Enable / disable extensions to match config"
echo " • NOT reinstall extensions already in correct state"
echo
read -rp "Continue? [Enter = yes | Ctrl+C = cancel] "

echo
echo "--------------------------------------------------"
echo " Reconciling extensions state"
echo "--------------------------------------------------"
echo

# --------------------------------------------------
# Helper functions
# --------------------------------------------------

is_installed() {
  gnome-extensions list | grep -qx "$1"
}

is_enabled() {
  gnome-extensions list --enabled | grep -qx "$1"
}

is_disabled() {
  gnome-extensions list --disabled | grep -qx "$1"
}

# --------------------------------------------------
# Main loop
# --------------------------------------------------

while IFS=":" read -r EXT_ID DESIRED_STATE; do
  [[ -z "$EXT_ID" ]] && continue
  [[ "$EXT_ID" =~ ^# ]] && continue

  echo "→ $EXT_ID"

  if is_installed "$EXT_ID"; then
    echo "  status : installed"
  else
    echo "  status : NOT installed"
    echo "  action : install required"
    echo
    echo "⚠️  Automatic installation of GNOME extensions"
    echo "    is NOT yet implemented."
    echo "    Install manually from:"
    echo "    https://extensions.gnome.org/extension/"
    echo
    read -rp "Press Enter to continue to next extension..."
    echo
    continue
  fi

  if [[ "$DESIRED_STATE" == "enabled" ]]; then
    if is_enabled "$EXT_ID"; then
      echo "  state  : already enabled"
      echo "  action : none"
    else
      echo "  state  : disabled"
      echo "  action : enabling"
      gnome-extensions enable "$EXT_ID"
      echo "  result : enabled"
    fi
  fi

  if [[ "$DESIRED_STATE" == "disabled" ]]; then
    if is_disabled "$EXT_ID"; then
      echo "  state  : already disabled"
      echo "  action : none"
    else
      echo "  state  : enabled"
      echo "  action : disabling"
      gnome-extensions disable "$EXT_ID"
      echo "  result : disabled"
    fi
  fi

  echo
done < "$CONF_FILE"

# --------------------------------------------------
# Completion
# --------------------------------------------------

echo "=================================================="
echo " Extensions reconciliation complete"
echo "=================================================="
echo
echo "If GNOME Shell was restarted or extensions"
echo "behave unexpectedly, log out and back in."
echo
read -rp "Press Enter to return to menu..."
