#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/extensions.conf"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install_extensions.log"

log() { echo "$*" | tee -a "$LOG_FILE"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

get_gnome_shell_version() {
  # "GNOME Shell 46.0" -> "46"
  local v
  v="$(gnome-shell --version 2>/dev/null | awk '{print $3}' || true)"
  echo "${v%%.*}"
}

prompt_continue() {
  local msg="$1"
  if has_cmd gum; then
    gum confirm "$msg"
  else
    echo "$msg"
    read -r -p "Continue? [y/N]: " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
  fi
}

ensure_deps_ubuntu() {
  log "Ensuring dependencies (Ubuntu): curl, jq, unzip, gnome-shell-extensions..."
  sudo apt-get update -y | tee -a "$LOG_FILE"
  sudo apt-get install -y curl jq unzip gnome-shell-extensions | tee -a "$LOG_FILE"
}

# Fetch latest compatible version_tag for a UUID from extensions.gnome.org
# Based on the common approach of using extension-query and shell_version_map pk max. :contentReference[oaicite:0]{index=0}
fetch_version_tag() {
  local uuid="$1"
  local q url json tag

  url="https://extensions.gnome.org/extension-query/?search=${uuid}"
  json="$(curl -fsSL "$url")" || return 1

  # Try to find the exact UUID match in results; otherwise fall back to first hit.
  tag="$(
    echo "$json" | jq -r --arg u "$uuid" '
      (.extensions // [])
      | (map(select(.uuid == $u)) | .[0] // .[0])
      | (.shell_version_map | map(.pk) | max // empty)
    ' 2>/dev/null
  )"

  [[ -n "${tag:-}" && "${tag:-}" != "null" ]] || return 1
  echo "$tag"
}

download_extension_zip() {
  local uuid="$1"
  local version_tag="$2"
  local out_zip="$3"

  local dl="https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}"
  curl -fsSL -o "$out_zip" "$dl"
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

install_if_missing_ubuntu() {
  local uuid="$1"
  local tmpdir zip tag

  if is_installed "$uuid"; then
    log "  status : installed"
    log "  action : install skipped (already installed)"
    return 0
  fi

  log "  status : missing"
  log "  action : installing from extensions.gnome.org"

  tag="$(fetch_version_tag "$uuid")" || {
    log "  ERROR  : could not determine version_tag for $uuid (extension-query)"
    return 1
  }

  tmpdir="$(mktemp -d)"
  zip="$tmpdir/${uuid}.zip"

  download_extension_zip "$uuid" "$tag" "$zip" || {
    log "  ERROR  : download failed for $uuid"
    rm -rf "$tmpdir"
    return 1
  }

  # gnome-extensions install expects a zip pack. :contentReference[oaicite:1]{index=1}
  gnome-extensions install --force "$zip" | tee -a "$LOG_FILE" || {
    log "  ERROR  : gnome-extensions install failed for $uuid"
    rm -rf "$tmpdir"
    return 1
  }

  rm -rf "$tmpdir"
  log "  OK     : installed $uuid"
}

reconcile_state() {
  local uuid="$1"
  local desired="$2"

  if ! is_installed "$uuid"; then
    log "  state  : not installed"
    log "  action : cannot reconcile (missing)"
    return 0
  fi

  if [[ "$desired" == "enabled" ]]; then
    if is_enabled "$uuid"; then
      log "  state  : already enabled"
      log "  action : none"
    else
      log "  state  : disabled"
      log "  action : enabling"
      gnome-extensions enable "$uuid" | tee -a "$LOG_FILE" || true
    fi
  elif [[ "$desired" == "disabled" ]]; then
    if is_disabled "$uuid"; then
      log "  state  : already disabled"
      log "  action : none"
    else
      log "  state  : enabled"
      log "  action : disabling"
      gnome-extensions disable "$uuid" | tee -a "$LOG_FILE" || true
    fi
  else
    log "  state  : unknown desired state '$desired'"
    log "  action : none"
  fi
}

main() {
  : > "$LOG_FILE"

  log "=================================================="
  log "[extensions] GNOME Extensions Install + Reconcile"
  log "=================================================="
  log "Date: $(date)"
  log "Log: $LOG_FILE"
  log ""

  if ! has_cmd gnome-extensions; then
    log "GNOME not detected (gnome-extensions missing)."
    log "Skipping extensions setup."
    exit 0
  fi

  local distro shell_major
  distro="$(detect_distro)"
  shell_major="$(get_gnome_shell_version || true)"

  log "Detected distro: $distro"
  log "GNOME Shell major: ${shell_major:-unknown}"
  log ""

  if [[ ! -f "$CONF_FILE" ]]; then
    log "ERROR: extensions.conf not found: $CONF_FILE"
    exit 1
  fi

  if [[ "$distro" == "ubuntu" || "$distro" == "debian" ]]; then
    prompt_continue "This will download and install GNOME extensions from extensions.gnome.org, then enable/disable them per extensions.conf. Continue?" || {
      log "Aborted by user."
      exit 0
    }
    ensure_deps_ubuntu
  else
    log "NOTE: Non-Ubuntu distro detected. This script currently focuses on Ubuntu install support."
    log "It will still reconcile enable/disable state for already-installed extensions."
    log ""
  fi

  log "Reconciling extensions state..."
  log ""

  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "${line// /}" ]] && continue
    [[ "${line:0:1}" == "#" ]] && continue

    # Format: uuid|enabled OR uuid|disabled
    local uuid desired
    uuid="$(echo "$line" | awk -F'|' '{print $1}')"
    desired="$(echo "$line" | awk -F'|' '{print $2}')"
    uuid="${uuid//[$'\t\r\n ']/}"
    desired="${desired//[$'\t\r\n ']/}"

    [[ -z "$uuid" ]] && continue
    [[ -z "$desired" ]] && desired="enabled"

    log "→ $uuid"

    if [[ "$distro" == "ubuntu" || "$distro" == "debian" ]]; then
      install_if_missing_ubuntu "$uuid" || {
        log "  ERROR  : failed processing $uuid"
        log ""
        continue
      }
    else
      if is_installed "$uuid"; then
        log "  status : installed"
      else
        log "  status : missing"
        log "  action : install skipped on $distro"
      fi
    fi

    reconcile_state "$uuid" "$desired"
    log ""
  done < "$CONF_FILE"

  log "=================================================="
  log " Extensions install + reconciliation complete"
  log "=================================================="
}

main "$@"
