#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# GNOME Extensions Installer (INTERACTIVE + TTY SAFE)
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
  echo "Skipping GNOME extensions setup."
  echo
  read -r -p "Press Enter to return to menu..." </dev/tty
  exit 0
fi

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: extensions.conf not found:"
  echo "  $CONF_FILE"
  echo
  read -r -p "Press Enter to return to menu..." </dev/tty
  exit 1
fi

echo "Detected:"
gnome-shell --version
echo

echo "This will reconcile GNOME extensions state:"
echo " • Enable / disable installed extensions"
echo " • Skip reinstall if already correct"
echo " • Never hide output"
echo
read -r -p "Press Enter to continue (Ctrl+C to cancel)..." </dev/tty

echo
echo "--------------------------------------------------"
echo " Reconciling extensions state"
echo "--------------------------------------------------"
echo

# --------------------------------------------------
# Helpers
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

  if ! is_installed "$EXT_ID"; then
    echo "  status : NOT installed"
    echo "  action : manual install required"
    echo "  URL    : https://extensions.gnome.org"
    echo
    read -r -p "Press Enter to continue..." </dev/tty
    echo
    continue
  fi

  echo "  status : installed"

  case "$DESIRED_STATE" in
    enabled)
      if is_enabled "$EXT_ID"; then
        echo "  state  : already enabled"
        echo "  action : none"
      else
        echo "  state  : disabled"
        echo "  action : enabling"
        gnome-extensions enable "$EXT_ID"
        echo "  result : enabled"
      fi
      ;;
    disabled)
      if is_disabled "$EXT_ID"; then
        echo "  state  : already disabled"
        echo "  action : none"
      else
        echo "  state  : enabled"
        echo "  action : disabling"
        gnome-extensions disable "$EXT_ID"
        echo "  result : disabled"
      fi
      ;;
    *)
      echo "  WARNING: unknown desired state '$DESIRED_STATE'"
      ;;
  esac

  echo
done < "$CONF_FILE"

# --------------------------------------------------
# Completion
# --------------------------------------------------

echo "=================================================="
echo " Extensions reconciliation complete"
echo "=================================================="
echo
echo "If extensions misbehave, log out and log back in."
echo
read -r -p "Press Enter to return to menu..." </dev/tty
