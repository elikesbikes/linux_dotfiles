#!/usr/bin/env bash
set -uo pipefail

# ==================================================
# verify_core.sh
# Audit-only check for the "core" category.
# Exits non-zero with the number of failed checks.
# ==================================================

echo "======================================"
echo " VERIFY CORE"
echo "======================================"

FAIL=0

check_cmd() {
  local label="$1" cmd="$2"
  echo -n "• $label : "
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "OK ($(command -v "$cmd"))"
  else
    echo "MISSING"
    FAIL=$((FAIL+1))
  fi
}

check_file() {
  local label="$1" path="$2"
  echo -n "• $label : "
  if [[ -e "$path" ]]; then
    echo "OK ($path)"
  else
    echo "MISSING ($path)"
    FAIL=$((FAIL+1))
  fi
}

check_cmd "sudo"    sudo

# Enforce the TARS baseline: classic sudo, never sudo-rs.
echo -n "• sudo is classic (not sudo-rs) : "
if command -v sudo >/dev/null 2>&1 && sudo --version 2>&1 | head -n1 | grep -qi 'sudo-rs'; then
  echo "FAIL (sudo-rs active)"
  FAIL=$((FAIL+1))
else
  echo "OK"
fi

check_cmd "ssh"     ssh
check_cmd "flatpak" flatpak
check_cmd "kitty"   kitty
check_cmd "node"    node

# Dynamic MOTD is Ubuntu/Debian-only; skip the check elsewhere.
if [[ -d /etc/update-motd.d ]]; then
  echo -n "• dynamic MOTD disabled : "
  _motd_left=$(find /etc/update-motd.d -maxdepth 1 -mindepth 1 -exec test -x {} \; -print 2>/dev/null | wc -l)
  if [[ "$_motd_left" -eq 0 ]]; then
    echo "OK"
  else
    echo "ENABLED: ${_motd_left} fragment(s) executable (run core/install_motd.sh)"
    FAIL=$((FAIL+1))
  fi
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "✓ Core verification PASSED"
else
  echo "✗ Core verification FAILED ($FAIL issues)"
fi

exit "$FAIL"
