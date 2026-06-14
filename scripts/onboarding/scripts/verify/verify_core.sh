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
check_file "sudoers deployed" /etc/sudoers.d/ecloaiza-nopasswd

# Default editor should be nvim (Debian `editor` alternative).
echo -n "• default editor is nvim : "
EDITOR_VAL="$(update-alternatives --query editor 2>/dev/null | awk -F': ' '/^Value:/{print $2}')"
if [[ "$EDITOR_VAL" == *nvim ]]; then
  echo "OK ($EDITOR_VAL)"
else
  echo "FAIL (${EDITOR_VAL:-unset})"
  FAIL=$((FAIL+1))
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "✓ Core verification PASSED"
else
  echo "✗ Core verification FAILED ($FAIL issues)"
fi

exit "$FAIL"
