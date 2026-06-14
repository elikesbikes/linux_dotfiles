#!/usr/bin/env bash
set -uo pipefail

# ==================================================
# verify_desktop.sh
# Audit-only check for the "desktop" category.
# Exits non-zero with the number of failed checks.
# ==================================================

echo "======================================"
echo " VERIFY DESKTOP"
echo "======================================"

FAIL=0

check_pkg() {
  local label="$1" pkg="$2"
  echo -n "• $label : "
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    echo "OK (dpkg: $pkg)"
  else
    echo "MISSING"
    FAIL=$((FAIL+1))
  fi
}

check_snap() {
  local label="$1" app="$2"
  echo -n "• $label : "
  if command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | awk '{print $1}' | grep -qx "$app"; then
    echo "OK (snap: $app)"
  else
    echo "MISSING"
    FAIL=$((FAIL+1))
  fi
}

check_flatpak() {
  local label="$1" app="$2"
  echo -n "• $label : "
  if command -v flatpak >/dev/null 2>&1 && flatpak list --app 2>/dev/null | awk '{print $1}' | grep -qx "$app"; then
    echo "OK (flatpak: $app)"
  else
    echo "MISSING"
    FAIL=$((FAIL+1))
  fi
}

# Native APT
check_pkg "timeshift"      timeshift
check_pkg "kitty"          kitty
check_pkg "spotify-client" spotify-client
check_pkg "rustdesk"       rustdesk

# Snap
check_snap "todoist" todoist

# Flatpak
check_flatpak "BlueBubbles"  app.bluebubbles.BlueBubbles
check_flatpak "SyncThingy"   com.github.zocker_160.SyncThingy
check_flatpak "Yubico Auth"  com.yubico.yubioath
check_flatpak "Clapgrep"     de.leopoldluley.Clapgrep
check_flatpak "Warehouse"    io.github.flattool.Warehouse
check_flatpak "Stimulator"   io.github.sigmasd.stimulator
check_flatpak "Resources"    net.nokyan.Resources
check_flatpak "Cryptomator"  org.cryptomator.Cryptomator

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "✓ Desktop verification PASSED"
else
  echo "✗ Desktop verification FAILED ($FAIL issues)"
fi

exit "$FAIL"
