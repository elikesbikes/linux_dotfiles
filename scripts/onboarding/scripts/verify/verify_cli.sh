#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/verify_cli.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VERIFY CLI ==="

fail=0

check_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null; then
    echo "OK: $name"
  else
    echo "FAIL: $name missing"
    fail=1
  fi
}

check_cmd exa || check_cmd eza
check_cmd fastfetch
check_cmd stow
check_cmd zoxide
check_cmd direnv
check_cmd figlet
check_cmd starship
check_cmd nvim

echo "Checking yazi (snap)..."
if snap list 2>/dev/null | awk '{print $1}' | grep -qx yazi; then
  echo "OK: yazi snap installed"
else
  echo "FAIL: yazi snap missing"
  fail=1
fi

exit $fail
