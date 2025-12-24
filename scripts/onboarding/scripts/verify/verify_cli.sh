#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: verify_cli.sh
# Version: 1.0.2
# Date: 2025-12-23
# Author: Tars (ELIKESBIKES)
#
# Changelog:
#   1.0.2 - Experimental: return status via echo and
#           always exit 0 to avoid aborting caller
#           under `set -e`.
#   1.0.1 - Baseline troubleshooting version.
# ==================================================

echo "======================================"
echo " VERIFY CLI"
echo "======================================"

fail=0

check_cmd() {
  local name="$1"

  if command -v "$name" >/dev/null 2>&1; then
    echo "✔ $name : OK"
  else
    echo "✘ $name : MISSING"
    fail=1
  fi
}

# exa / eza compatibility
if command -v exa >/dev/null 2>&1; then
  echo "✔ exa : OK"
elif command -v eza >/dev/null 2>&1; then
  echo "✔ eza : OK (replacement for exa)"
else
  echo "✘ exa/eza : MISSING"
  fail=1
fi

check_cmd fastfetch
check_cmd stow
check_cmd zoxide
check_cmd direnv
check_cmd figlet
check_cmd starship
check_cmd nvim

echo
echo "Checking yazi (snap)..."
if command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | awk '{print $1}' | grep -qx yazi; then
  echo "✔ yazi : OK (snap)"
else
  echo "✘ yazi : MISSING (snap)"
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "✓ CLI verification PASSED"
else
  echo "⚠ CLI verification FAILED"
fi

# EXPERIMENTAL CHANGE:
# Do NOT propagate non-zero exit to caller
exit 0
