#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/verify_core.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VERIFY CORE ==="

fail=0

echo "Checking flatpak..."
if ! command -v flatpak >/dev/null; then
  echo "FAIL: flatpak missing"
  fail=1
else
  echo "OK: flatpak present"
fi

echo "Checking flathub remote..."
if ! flatpak remotes | awk '{print $1}' | grep -qx flathub; then
  echo "FAIL: flathub not configured"
  fail=1
else
  echo "OK: flathub configured"
fi

echo "Checking ssh..."
if ! command -v ssh >/dev/null; then
  echo "FAIL: ssh missing"
  fail=1
else
  ssh -V || true
  echo "OK: ssh present"
fi

exit $fail
