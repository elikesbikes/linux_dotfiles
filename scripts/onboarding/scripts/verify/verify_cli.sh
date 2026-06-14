#!/usr/bin/env bash
set -uo pipefail

# ==================================================
# verify_cli.sh
# Audit-only check for the "cli" category.
# Exits non-zero with the number of failed checks.
# ==================================================

echo "======================================"
echo " VERIFY CLI"
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

# exa was replaced upstream by eza; accept either.
echo -n "• exa/eza : "
if command -v exa >/dev/null 2>&1 || command -v eza >/dev/null 2>&1; then
  echo "OK"
else
  echo "MISSING"
  FAIL=$((FAIL+1))
fi

check_cmd "direnv"   direnv
check_cmd "fastfetch" fastfetch
check_cmd "figlet"   figlet
check_cmd "neovim"   nvim
check_cmd "starship" starship
check_cmd "stow"     stow
check_cmd "yazi"     yazi
check_cmd "zoxide"   zoxide
check_cmd "unison"   unison
check_pkg "build-essential" build-essential

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "✓ CLI verification PASSED"
else
  echo "✗ CLI verification FAILED ($FAIL issues)"
fi

exit "$FAIL"
