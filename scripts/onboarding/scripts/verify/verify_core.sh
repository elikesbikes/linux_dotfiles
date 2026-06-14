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

check_cmd "sudo"    sudo
check_cmd "ssh"     ssh
check_cmd "flatpak" flatpak
check_cmd "kitty"   kitty

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "✓ Core verification PASSED"
else
  echo "✗ Core verification FAILED ($FAIL issues)"
fi

exit "$FAIL"
