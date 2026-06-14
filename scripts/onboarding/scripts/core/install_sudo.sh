#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_sudo.sh
# Version: 2.0.0
#
# Versioning:
# 2.0.0 - Enforce the TARS baseline: traditional sudo, never sudo-rs.
#         - Ubuntu 25.10 ships sudo-rs as the default `sudo`. sudo-rs does
#           not implement directives our sudoers fragments use (log_output,
#           iolog_dir, per-command `Defaults!`), so it breaks the existing
#           policy. This script detects sudo-rs and switches the host back to
#           classic sudo via apt + the Debian alternatives system
#           (the supported revert path documented by Ubuntu).
#         - Idempotent: a host already on classic sudo (e.g. TARS) is a no-op.
# 1.0.0 - Initial implementation:
#         - State-based idempotency via XDG state marker
#         - Ensure sudo is installed via apt
#         - Report sudo version details (sudo -V)
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="2.0.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/sudo"

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Helpers
# --------------------------------------------------
as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# True when the active `sudo` is the Rust reimplementation (sudo-rs).
# Mirrors the detection in sync-sudoers.sh: sudo-rs prints "sudo-rs" in its
# version banner. `--version` does not require authentication.
is_sudo_rs() {
  command -v sudo >/dev/null 2>&1 || return 1
  sudo --version 2>&1 | head -n1 | grep -qi 'sudo-rs'
}

report_version() {
  echo ""
  echo "sudo version details:"
  sudo -V 2>/dev/null | head -n 6 || true
}

# Install classic sudo and, if `sudo` is managed by alternatives (Ubuntu
# 25.10+), select the non-rs implementation so /usr/bin/sudo is classic sudo.
ensure_classic_sudo() {
  echo "Installing/ensuring traditional sudo via apt..."
  # Core is the category allowed to refresh apt.
  as_root apt-get update
  as_root apt-get install -y sudo

  if command -v update-alternatives >/dev/null 2>&1 \
     && update-alternatives --query sudo >/dev/null 2>&1; then
    echo "sudo is managed by update-alternatives; selecting classic sudo..."
    local alt
    while IFS= read -r alt; do
      [[ -x "$alt" ]] || continue
      if "$alt" --version 2>&1 | head -n1 | grep -qi 'sudo-rs'; then
        echo "  skip (sudo-rs): $alt"
        continue
      fi
      echo "  selecting classic sudo: $alt"
      as_root update-alternatives --set sudo "$alt"
      break
    done < <(update-alternatives --list sudo 2>/dev/null)
  fi
}

# --------------------------------------------------
# State-based idempotency check (authoritative)
# --------------------------------------------------
if [[ -f "$STATE_FILE" ]]; then
  echo "STATE: sudo already marked as configured ($STATE_FILE)"
  report_version
  echo "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Fast path: already on the TARS baseline (classic sudo present)
# --------------------------------------------------
if command -v sudo >/dev/null 2>&1 && ! is_sudo_rs; then
  echo "Traditional sudo already active: $(command -v sudo)"
  report_version
  echo "Matches TARS baseline. Marking as configured."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Switch to / install classic sudo
# --------------------------------------------------
if is_sudo_rs; then
  echo "Detected sudo-rs — switching host to traditional sudo (TARS baseline)."
  echo "Reason: sudo-rs rejects directives our sudoers fragments rely on"
  echo "(log_output, iolog_dir, per-command Defaults!)."
else
  echo "sudo not present — installing traditional sudo."
fi

ensure_classic_sudo

# --------------------------------------------------
# Post-install validation: classic sudo, never sudo-rs
# --------------------------------------------------
if command -v sudo >/dev/null 2>&1 && ! is_sudo_rs; then
  echo "SUCCESS: traditional sudo active: $(command -v sudo)"
  report_version
  touch "$STATE_FILE"
else
  echo "FAIL: sudo missing or still sudo-rs after switch."
  echo "Inspect: update-alternatives --display sudo"
  exit 1
fi

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
