#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_motd.sh
# Version: 2.0.0
#
# Versioning:
# 1.0.0 - Initial implementation: disabled every dynamic MOTD fragment except
#         00-header (the static "Welcome to Ubuntu ..." line).
# 2.0.0 - Remove the WHOLE SSH-login banner, including the "Welcome to Ubuntu"
#         line (00-header). Nothing is printed by pam_motd anymore.
#         - Resolves symlinked fragments (e.g. 50-landscape-sysinfo ->
#           /usr/share/landscape/...), since the exec bit that run-parts checks
#           lives on the target, not the link.
#         - Installs /etc/apt/apt.conf.d/99-no-motd so a package upgrade that
#           restores a fragment's exec bit (update-notifier, landscape,
#           ubuntu-pro-client, ...) is undone automatically afterwards.
#         - Idempotency is based on the real state of the fragments, not only
#           the state marker, so re-running always repairs drift.
#
# Scope note: Ubuntu/Debian-only. Other distros (e.g. Arch/Omarchy on tars)
# don't ship update-motd.d, so this is a clean no-op there.
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="2.0.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/motd"

mkdir -p "$LOG_DIR" "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Distro guard — Ubuntu/Debian only
# --------------------------------------------------
if [ -r /etc/os-release ]; then
  . /etc/os-release
fi

if [ "${ID:-}" != "ubuntu" ] && ! echo "${ID_LIKE:-}" | grep -qi debian; then
  echo "INFO: Not a Debian/Ubuntu system. Skipping."
  exit 0
fi

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

MOTD_DIR="/etc/update-motd.d"
APT_HOOK="/etc/apt/apt.conf.d/99-no-motd"

if [[ ! -d "$MOTD_DIR" ]]; then
  echo "INFO: $MOTD_DIR not present. Nothing to disable."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Disable EVERY dynamic MOTD fragment (header, help text, sysinfo, news,
# ESM/Pro, updates-available, release-upgrade, reboot-required, ...).
# `-x` follows symlinks, so a symlinked fragment still counts as enabled;
# resolve it so the exec bit is cleared on the real file.
# --------------------------------------------------
echo "Disabling all fragments in $MOTD_DIR..."
changed=0
for frag in "$MOTD_DIR"/*; do
  [[ -e "$frag" ]] || continue
  if [[ -x "$frag" ]]; then
    real="$(readlink -f -- "$frag")"
    echo "  - disabling $(basename "$frag")$([[ "$real" != "$frag" ]] && echo " (-> $real)")"
    as_root chmod -x "$real"
    changed=$((changed + 1))
  fi
done
[[ "$changed" -eq 0 ]] && echo "  (all fragments already disabled)"

# --------------------------------------------------
# Keep it disabled across package upgrades (they restore exec bits).
# NOTE: apt.conf strings have no \" escape, so keep the command free of nested
# quotes; chmod follows symlinks given as arguments, so the sysinfo link is covered.
# --------------------------------------------------
HOOK_CONTENT='// Managed by onboarding/core/install_motd.sh - keep the SSH login banner off.
DPkg::Post-Invoke { "chmod -x /etc/update-motd.d/* 2>/dev/null; true"; };'

if [[ "$(cat "$APT_HOOK" 2>/dev/null || true)" != "$HOOK_CONTENT" ]]; then
  echo "Installing apt post-invoke hook: $APT_HOOK"
  printf '%s\n' "$HOOK_CONTENT" | as_root tee "$APT_HOOK" >/dev/null
else
  echo "apt post-invoke hook already in place."
fi

# --------------------------------------------------
# Disable the motd-news fetcher (the "Canonical Workshop"-style ads)
# --------------------------------------------------
if [[ -f /etc/default/motd-news ]]; then
  echo "Disabling motd-news fetcher..."
  as_root sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^motd-news.timer'; then
  as_root systemctl disable --now motd-news.timer >/dev/null 2>&1 || true
fi

# --------------------------------------------------
# Verify real state, then mark success
# --------------------------------------------------
left=0
for frag in "$MOTD_DIR"/*; do
  [[ -e "$frag" && -x "$frag" ]] && left=$((left + 1))
done
if [[ "$left" -ne 0 ]]; then
  echo "FAIL: $left MOTD fragment(s) still executable in $MOTD_DIR"
  exit 1
fi

touch "$STATE_FILE"

echo "SUCCESS: SSH login banner fully disabled (no executable fragments in $MOTD_DIR)"

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
