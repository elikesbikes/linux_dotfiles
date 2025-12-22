#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/extensions.conf"

echo "======================================"
echo " VERIFY EXTENSIONS (audit only)"
echo "======================================"

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "GNOME not detected — skipping verification."
  exit 0
fi

if [[ ! -f "$CONF_FILE" ]]; then
  echo "ERROR: extensions.conf missing"
  exit 1
fi

is_installed() {
  gnome-extensions list | grep -qx "$1"
}

is_enabled() {
  gnome-extensions list --enabled | grep -qx "$1"
}

FAIL=0

while IFS='=' read -r EXT STATE; do
  [[ -z "$EXT" || "$EXT" =~ ^# ]] && continue

  EXT="$(echo "$EXT" | xargs)"
  STATE="$(echo "$STATE" | xargs)"

  echo -n "• $EXT : "

  if ! is_installed "$EXT"; then
    echo "MISSING"
    ((FAIL++))
    continue
  fi

  if [[ "$STATE" == "enabled" ]]; then
    is_enabled "$EXT" && echo "OK (enabled)" || {
      echo "FAIL (disabled)"
      ((FAIL++))
    }
  else
    is_enabled "$EXT" && {
      echo "FAIL (enabled)"
      ((FAIL++))
    } || echo "OK (disabled)"
  fi
done <"$CONF_FILE"

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "✓ Extensions verification PASSED"
else
  echo "✗ Extensions verification FAILED ($FAIL issues)"
fi

exit "$FAIL"
