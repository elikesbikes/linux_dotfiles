#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_motd.sh
# Version: 1.0.0
#
# Versioning:
# 1.0.0 - Initial implementation:
#         - Disables Ubuntu's dynamic MOTD (system info block, news/ads,
#           ESM/Pro nags, release-upgrade notices, etc.) shown on every
#           SSH login, leaving only the static "Welcome to Ubuntu ..." line.
#         - State-based idempotency via XDG state marker.
#
# Scope note: Ubuntu/Debian-only. Other distros (e.g. Arch/Omarchy on tars)
# don't ship update-motd.d, so this is a clean no-op there.
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

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

# --------------------------------------------------
# State-based idempotency check
# --------------------------------------------------
if [[ -f "$STATE_FILE" ]]; then
  echo "STATE: dynamic MOTD already disabled ($STATE_FILE)"
  echo "Nothing to do. Exiting."
  exit 0
fi

MOTD_DIR="/etc/update-motd.d"

if [[ ! -d "$MOTD_DIR" ]]; then
  echo "INFO: $MOTD_DIR not present. Nothing to disable."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Disable every dynamic MOTD fragment except the static header
# (00-header prints "Welcome to Ubuntu ... (GNU/Linux ...)")
# --------------------------------------------------
echo "Disabling dynamic MOTD fragments in $MOTD_DIR..."
for frag in "$MOTD_DIR"/*; do
  [[ -f "$frag" ]] || continue
  case "$(basename "$frag")" in
    00-header)
      continue
      ;;
  esac
  if [[ -x "$frag" ]]; then
    echo "  - disabling $(basename "$frag")"
    as_root chmod -x "$frag"
  fi
done

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

touch "$STATE_FILE"

echo "SUCCESS: dynamic MOTD disabled — only the static Ubuntu welcome line remains"

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
