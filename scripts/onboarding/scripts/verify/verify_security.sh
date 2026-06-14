#!/usr/bin/env bash
set -uo pipefail

# ==================================================
# verify_security.sh
# Audit-only check for the "security" category (Proton suite).
# Uses onboarding state markers since the Proton apps are
# installed from .deb packages with varied package names.
# Exits non-zero with the number of failed checks.
# ==================================================

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"

echo "======================================"
echo " VERIFY SECURITY (Proton suite)"
echo "======================================"

FAIL=0

check_marker() {
  local label="$1" marker="$2"
  echo -n "• $label : "
  if [[ -f "$STATE_DIR/$marker" ]]; then
    echo "OK (marker: $marker)"
  else
    echo "MISSING"
    FAIL=$((FAIL+1))
  fi
}

check_marker "Proton VPN"           proton-vpn
check_marker "Proton Mail Desktop"  proton-mail-desktop
check_marker "Proton Mail Bridge"   proton-mail-bridge
check_marker "Proton Pass"          proton-pass
check_marker "Proton Authenticator" proton-authenticator

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "✓ Security verification PASSED"
else
  echo "✗ Security verification FAILED ($FAIL issues)"
fi

exit "$FAIL"
