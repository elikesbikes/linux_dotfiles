#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/verify_security.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VERIFY SECURITY ==="

fail=0

check_pkg() {
  local pkg="$1"
  if dpkg -l | awk '{print $2}' | grep -qx "$pkg"; then
    echo "OK: $pkg"
  else
    echo "FAIL: $pkg missing"
    fail=1
  fi
}

check_pkg proton-vpn-gnome
check_pkg protonvpn-cli
check_pkg proton-bridge
check_pkg proton-authenticator

echo "Checking Proton Pass (Flatpak)..."
if flatpak list --app | awk '{print $1}' | grep -qx me.proton.Pass; then
  echo "OK: Proton Pass installed"
else
  echo "FAIL: Proton Pass missing"
  fail=1
fi

exit $fail
