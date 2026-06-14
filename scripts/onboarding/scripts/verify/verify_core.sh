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
check_cmd "ssh"     ssh
check_cmd "flatpak" flatpak
check_cmd "kitty"   kitty
check_cmd "node"    node
check_file "sudoers deployed" /etc/sudoers.d/ecloaiza-nopasswd

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "✓ Core verification PASSED"
else
  echo "✗ Core verification FAILED ($FAIL issues)"
fi

exit "$FAIL"
