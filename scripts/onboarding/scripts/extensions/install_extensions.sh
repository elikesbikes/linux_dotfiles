#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# GNOME Extensions: Auto-install + Reconcile (NO PROMPTS)
# - Supports extensions.conf lines like:
#     uuid|enabled
#     uuid=enabled
#     uuid:enabled
# - Auto-installs missing extensions on Ubuntu via:
#     - extensions.gnome.org (download zip + gnome-extensions install)
#     - apt fallback for some Ubuntu-provided extensions
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
  local s="$1"
  # shellcheck disable=SC2001
  echo "$(echo "$s" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
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
    # If state missing, default enabled
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

# For some Ubuntu-provided extensions, installing via apt is the right move on greenfield.
ubuntu_apt_install_for_uuid() {
  local uuid="$1"

  case "$uuid" in
    ubuntu-dock@ubuntu.com)
      sudo apt-get install -y gnome-shell-extension-ubuntu-dock || true
      ;;
    ding@rastersoft.com)
      # Desktop Icons NG on Ubuntu
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

# ---- extensions.gnome.org helpers ----
# query:
# https://extensions.gnome.org/extension-query/?search=<uuid>
# download:
# https://extensions.gnome.org/download-extension/<uuid>.shell-extension.zip?version_tag=<tag>
fetch_version_tag() {
  local uuid="$1"
  local url json

  url="https://extensions.gnome.org/extension-query/?search=${uuid}"
  json="$(curl -fsSL "$url")" || return 1

  # Find exact match first; else first result.
  # Then pick max pk from shell_version_map (latest compatible build on server side).
  echo "$json" | jq -r --arg u "$uuid" '
    (.extensions // [])
    | (map(select(.uuid == $u)) | .[0] // .[0])
    | (.shell_version_map | map(.pk) | max // empty)
  ' 2>/dev/null
}

download_extension_zip() {
  local uuid="$1"
  local version_tag="$2"
  local out_zip="$3"

  local dl
  dl="https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}"
  curl -fsSL -o "$out_zip" "$dl"
}

install_from_ego() {
  local uuid="$1"

  local tag tmpdir zip
  tag="$(fetch_version_tag "$uuid" | tr -d '\r\n' || true)"
  if [[ -z "$tag" || "$tag" == "null" ]]; then
    log "  ERROR : could not get version_tag from extensions.gnome.org for $uuid"
    return 1
  fi

  tmpdir="$(mktemp -d)"
  zip="$tmpdir/${uuid}.zip"

  download_extension_zip "$uuid" "$tag" "$zip" || {
    log "  ERROR : download failed for $uuid"
    rm -rf "$tmpdir"
    return 1
  }

  # Install to user extensions (safe + repeatable)
  gnome-extensions install --force "$zip" >/dev/null 2>&1 || {
    log "  ERROR : gnome-extensions install failed for $uuid"
    rm -rf "$tmpdir"
    return 1
  }

  rm -rf "$tmpdir"
  return 0
}

ensure_installed() {
  local uuid="$1"
  local distro="$2"

  if is_installed "$uuid"; then
    log "  status : installed"
    log "  action : install skipped"
    return 0
  fi

  log "  status : missing"
  log "  action : installing"

  if [[ "$distro" == "ubuntu" || "$distro" == "debian" ]]; then
    # First try apt for known Ubuntu-provided extensions
    if ubuntu_apt_install_for_uuid "$uuid"; then
      if is_installed "$uuid"; then
        log "  OK     : installed via apt"
        return 0
      fi
      log "  WARN   : apt attempted but extension still missing (will try extensions.gnome.org)"
    fi

    # Then try extensions.gnome.org
    if install_from_ego "$uuid"; then
      if is_installed "$uuid"; then
        log "  OK     : installed via extensions.gnome.org"
        return 0
      fi
      log "  ERROR  : install reported success but extension still missing"
      return 1
    else
      log "  ERROR  : failed to install from extensions.gnome.org"
      return 1
    fi
  else
    log "  WARN   : automatic install not implemented for distro '$distro' (reconcile only)"
    return 1
  fi
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
  log "[extensions] Auto-install + Reconcile (NO PROMPTS)"
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

  # If we might need sudo, validate once up front (visible prompt if required)
  if [[ "$distro" == "ubuntu" || "$distro" == "debian" ]]; then
    log "Preparing system dependencies..."
    sudo -v
    ensure_deps_ubuntu
    log ""
  fi

  log "Processing extensions.conf..."
  log ""

  local any_fail=0

  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    local parsed uuid desired
    parsed="$(parse_line "$line" || true)"
    [[ -z "${parsed:-}" ]] && continue

    uuid="$(echo "$parsed" | awk '{print $1}')"
    desired="$(echo "$parsed" | awk '{print $2}')"

    log "→ $uuid"
    log "  desired: $desired"

    # Install missing if we can
    if ! is_installed "$uuid"; then
      if ! ensure_installed "$uuid" "$distro"; then
        any_fail=1
      fi
    else
      log "  status : installed"
    fi

    # Reconcile enable/disable regardless
    reconcile_state "$uuid" "$desired"
    log ""
  done < "$CONF_FILE"

  log "=================================================="
  if [[ "$any_fail" -eq 0 ]]; then
    log " Extensions install + reconcile COMPLETE (OK)"
  else
    log " Extensions install + reconcile COMPLETE (WITH ERRORS)"
    log " Check log: $LOG_FILE"
  fi
  log "=================================================="
}

main "$@"
