#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# GNOME Extensions (Ubuntu GNOME 46 production-safe)
#
# Strategy:
# - Ubuntu/Debian system extensions: install via apt (automatic)
# - Third-party extensions (extensions.gnome.org): DO NOT auto-install on Ubuntu GNOME 46
#   because CLI installs can "succeed" but not register. Instead:
#     - If missing: print manual install URL + continue
#     - If present: enforce enabled/disabled state
#
# Config formats supported in extensions.conf:
#   uuid|enabled
#   uuid=enabled
#   uuid:enabled
# ==================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/extensions.conf"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install_extensions.log"

log() { echo "$*"; echo "$*" >>"$LOG_FILE"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

gnome_shell_major() {
  local v
  v="$(gnome-shell --version 2>/dev/null | awk '{print $3}' || true)"  # e.g. 46.0
  echo "${v%%.*}"
}

trim() {
  # shellcheck disable=SC2001
  echo "$(echo "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
}

parse_line() {
  # Accept: uuid|state OR uuid=state OR uuid:state
  # Outputs: "uuid state"
  local line="$1"
  line="$(trim "$line")"

  [[ -z "$line" ]] && return 1
  [[ "${line:0:1}" == "#" ]] && return 1

  local uuid state
  if [[ "$line" == *"|"* ]]; then
    uuid="${line%%|*}"
    state="${line##*|}"
  elif [[ "$line" == *"="* ]]; then
    uuid="${line%%=*}"
    state="${line##*=}"
  elif [[ "$line" == *":"* ]]; then
    uuid="${line%%:*}"
    state="${line##*:}"
  else
    uuid="$line"
    state="enabled"
  fi

  uuid="$(trim "$uuid")"
  state="$(trim "$state")"
  [[ -z "$state" ]] && state="enabled"

  echo "$uuid $state"
}

is_installed() {
  local uuid="$1"
  gnome-extensions info "$uuid" >/dev/null 2>&1
}

is_enabled() {
  local uuid="$1"
  gnome-extensions list --enabled | grep -qx "$uuid"
}

is_disabled() {
  local uuid="$1"
  gnome-extensions list --disabled | grep -qx "$uuid"
}

ensure_deps_ubuntu() {
  log "Ensuring deps (Ubuntu): curl jq unzip gnome-shell-extensions"
  sudo apt-get update -y
  sudo apt-get install -y curl jq unzip gnome-shell-extensions
}

# Map known Ubuntu/system extensions to apt packages.
# Return 0 if we attempted apt install, 1 otherwise.
ubuntu_apt_install_for_uuid() {
  local uuid="$1"

  case "$uuid" in
    ubuntu-dock@ubuntu.com)
      sudo apt-get install -y gnome-shell-extension-ubuntu-dock || true
      ;;
    ding@rastersoft.com)
      sudo apt-get install -y gnome-shell-extension-desktop-icons-ng || true
      ;;
    tiling-assistant@ubuntu.com)
      sudo apt-get install -y gnome-shell-extension-tiling-assistant || true
      ;;
    ubuntu-appindicators@ubuntu.com)
      sudo apt-get install -y gnome-shell-extension-appindicator || true
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

ego_url_for_uuid() {
  # We cannot reliably derive the numeric extension ID without an API query,
  # but the UUID is still useful context. Provide the base site.
  # If you want direct per-extension URLs later, we can add an API lookup.
  echo "https://extensions.gnome.org"
}

reconcile_state() {
  local uuid="$1"
  local desired="$2"

  if ! is_installed "$uuid"; then
    log "  state  : not installed"
    log "  action : cannot reconcile"
    return 0
  fi

  case "$desired" in
    enabled)
      if is_enabled "$uuid"; then
        log "  state  : already enabled"
        log "  action : none"
      else
        log "  state  : disabled"
        log "  action : enabling"
        gnome-extensions enable "$uuid" >/dev/null 2>&1 || true
      fi
      ;;
    disabled)
      if is_disabled "$uuid"; then
        log "  state  : already disabled"
        log "  action : none"
      else
        log "  state  : enabled"
        log "  action : disabling"
        gnome-extensions disable "$uuid" >/dev/null 2>&1 || true
      fi
      ;;
    *)
      log "  WARN   : unknown desired state '$desired' (expected enabled/disabled)"
      ;;
  esac
}

main() {
  : >"$LOG_FILE"

  log "=================================================="
  log "[extensions] Ubuntu-safe reconcile (NO fake installs)"
  log "=================================================="
  log "Date: $(date)"
  log "Log : $LOG_FILE"
  log ""

  if ! has_cmd gnome-extensions; then
    log "GNOME not detected (gnome-extensions missing). Skipping."
    exit 0
  fi

  if [[ ! -f "$CONF_FILE" ]]; then
    log "ERROR: missing config: $CONF_FILE"
    exit 1
  fi

  local distro shell_major
  distro="$(detect_distro)"
  shell_major="$(gnome_shell_major || true)"

  log "Detected distro      : $distro"
  log "GNOME Shell (major)  : ${shell_major:-unknown}"
  log ""

  if [[ "$distro" == "ubuntu" || "$distro" == "debian" ]]; then
    log "Preparing system dependencies..."
    sudo -v
    ensure_deps_ubuntu
    log ""
  fi

  log "Processing extensions.conf..."
  log ""

  local any_fail=0
  local any_manual=0

  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    local parsed uuid desired
    parsed="$(parse_line "$line" || true)"
    [[ -z "${parsed:-}" ]] && continue

    uuid="$(echo "$parsed" | awk '{print $1}')"
    desired="$(echo "$parsed" | awk '{print $2}')"

    log "→ $uuid"
    log "  desired: $desired"

    if ! is_installed "$uuid"; then
      # Try apt for known Ubuntu/system extensions
      if [[ "$distro" == "ubuntu" || "$distro" == "debian" ]]; then
        if ubuntu_apt_install_for_uuid "$uuid"; then
          if is_installed "$uuid"; then
            log "  status : installed (via apt)"
          else
            log "  status : missing (apt attempted, still missing)"
            log "  action : manual install required"
            log "  source : $(ego_url_for_uuid "$uuid")"
            any_manual=1
            any_fail=1
          fi
        else
          # Third-party extension: on Ubuntu GNOME 46 we do NOT attempt CLI installs.
          log "  status : missing"
          log "  action : manual install required"
          log "  source : $(ego_url_for_uuid "$uuid")"
          any_manual=1
          any_fail=1
        fi
      else
        log "  status : missing"
        log "  action : install not implemented for distro '$distro'"
        any_fail=1
      fi
    else
      log "  status : installed"
    fi

    reconcile_state "$uuid" "$desired"
    log ""
  done < "$CONF_FILE"

  log "=================================================="
  if [[ "$any_fail" -eq 0 ]]; then
    log " Extensions reconcile COMPLETE (OK)"
  else
    log " Extensions reconcile COMPLETE (WITH WARNINGS)"
    if [[ "$any_manual" -eq 1 ]]; then
      log " Manual installs are required for some third-party extensions on Ubuntu GNOME 46."
    fi
    log " Check log: $LOG_FILE"
  fi
  log "=================================================="
}

main "$@"
