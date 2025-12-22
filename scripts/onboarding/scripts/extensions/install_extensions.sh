#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/extensions.conf"

echo "=================================================="
echo "[extensions] GNOME Extensions State Reconciliation"
echo "=================================================="

# --------------------------------------------------
# Preconditions
# --------------------------------------------------

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "GNOME not detected (gnome-extensions missing)."
  echo "Skipping extensions reconciliation."
  exit 0
fi

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: extensions.conf not found:"
  echo "  $CONF_FILE"
  exit 1
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

enable_ext() {
  gnome-extensions enable "$1" || true
}

disable_ext() {
  gnome-extensions disable "$1" || true
}

# --------------------------------------------------
# Reconciliation logic
# --------------------------------------------------

echo
echo "Reconciling extensions state..."
echo

while IFS='=' read -r EXT STATE; do
  # Skip comments / empty lines
  [[ -z "$EXT" || "$EXT" =~ ^# ]] && continue

  EXT="$(echo "$EXT" | xargs)"
  STATE="$(echo "$STATE" | xargs)"

  echo "→ $EXT"

  if ! is_installed "$EXT"; then
    echo "  status : NOT INSTALLED"
    echo "  action : none (greenfield-safe)"
    echo
    continue
  fi

  echo "  status : installed"

  case "$STATE" in
    enabled)
      if is_enabled "$EXT"; then
        echo "  state  : already enabled"
        echo "  action : none"
      else
        echo "  state  : disabled"
        echo "  action : enabling"
        enable_ext "$EXT"
      fi
      ;;
    disabled)
      if is_enabled "$EXT"; then
        echo "  state  : enabled"
        echo "  action : disabling"
        disable_ext "$EXT"
      else
        echo "  state  : already disabled"
        echo "  action : none"
      fi
      ;;
    *)
      echo "  WARNING: unknown desired state '$STATE'"
      ;;
  esac

  echo
done < "$CONF_FILE"

echo "=================================================="
echo " Extensions state reconciliation complete"
echo "=================================================="
