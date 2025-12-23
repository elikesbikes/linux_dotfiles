#!/usr/bin/env bash
# shellcheck shell=bash
#
# Helper rule:
# - stdout is DATA ONLY (returned values)
# - stderr is for logs / progress / errors

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_BASE/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
STATE_DIR="$STATE_BASE/installed"

mkdir -p "$LOG_DIR" "$STATE_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Proton Suite Installer"
echo "Policy: Official sources only | Idempotent | NO SNAP"
echo "Date: $(date)"
echo "Log : $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Distro guard
# --------------------------------------------------
if [ -r /etc/os-release ]; then
  . /etc/os-release
fi

if [ "${ID:-}" != "ubuntu" ] && ! echo "${ID_LIKE:-}" | grep -qi debian; then
  echo "INFO: Not a Debian/Ubuntu system. Skipping."
  exit 0
fi

# --------------------------------------------------
# Helpers
# --------------------------------------------------
apt_update() {
  sudo apt-get update -y
}

install_deps() {
  sudo apt-get install -y wget curl ca-certificates gnupg
}

download_deb() {
  local url="$1"
  local name="$2"
  local tmpdir path

  tmpdir="$(mktemp -d)"
  path="$tmpdir/$name"

  echo "Downloading $name" >&2
  if ! wget -q --show-progress -O "$path" "$url"; then
    echo "ERROR: Failed to download $url" >&2
    return 1
  fi

  echo "$path"
}

install_deb() {
  local deb="$1"
  sudo dpkg -i "$deb" && sudo apt-get -f install -y
}

mark_installed() {
  touch "$STATE_DIR/$1"
}

already_installed() {
  local marker="$1"
  if [ -f "$STATE_DIR/$marker" ]; then
    echo "INFO: $marker already installed, skipping."
    return 0
  fi
  return 1
}

# --------------------------------------------------
# Proton VPN
# https://protonvpn.com/support/official-linux-vpn-ubuntu
# --------------------------------------------------
install_proton_vpn() {
  already_installed proton-vpn && return

  echo "=== Proton VPN ==="

  local repo_deb
  if repo_deb="$(download_deb \
    "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb" \
    "protonvpn-stable-release.deb")"; then

    if install_deb "$repo_deb"; then
      sudo apt-get install -y proton-vpn-gnome-desktop
      mark_installed proton-vpn
      return
    fi
  fi

  echo "ERROR: Proton VPN install failed" >&2
}

# --------------------------------------------------
# Proton Mail Desktop
# --------------------------------------------------
install_proton_mail_desktop() {
  already_installed proton-mail-desktop && return

  echo "=== Proton Mail Desktop ==="

  local deb
  if deb="$(download_deb \
    "https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb" \
    "protonmail-desktop.deb")"; then

    if install_deb "$deb"; then
      mark_installed proton-mail-desktop
      return
    fi
  fi

  echo "ERROR: Proton Mail Desktop install failed" >&2
}

# --------------------------------------------------
# Proton Mail Bridge
# --------------------------------------------------
install_proton_mail_bridge() {
  already_installed proton-mail-bridge && return

  echo "=== Proton Mail Bridge ==="

  local deb
  if deb="$(download_deb \
    "https://proton.me/download/bridge/protonmail-bridge_3.21.2-1_amd64.deb" \
    "protonmail-bridge.deb")"; then

    if install_deb "$deb"; then
      mark_installed proton-mail-bridge
      return
    fi
  fi

  echo "ERROR: Proton Mail Bridge install failed" >&2
}

# --------------------------------------------------
# Proton Pass Desktop
# --------------------------------------------------
install_proton_pass() {
  already_installed proton-pass && return

  echo "=== Proton Pass Desktop ==="

  local deb
  if deb="$(download_deb \
    "https://proton.me/download/pass/linux/ProtonPass.deb" \
    "protonpass.deb")"; then

    if install_deb "$deb"; then
      mark_installed proton-pass
      return
    fi
  fi

  echo "ERROR: Proton Pass install failed" >&2
}

# --------------------------------------------------
# Proton Authenticator
# --------------------------------------------------
install_proton_authenticator() {
  already_installed proton-authenticator && return

  echo "=== Proton Authenticator ==="

  local deb
  if deb="$(download_deb \
    "https://proton.me/download/authenticator/linux/ProtonAuthenticator.deb" \
    "proton-authenticator.deb")"; then

    if install_deb "$deb"; then
      mark_installed proton-authenticator
      return
    fi
  fi

  echo "ERROR: Proton Authenticator install failed" >&2
}

# --------------------------------------------------
# Run
# --------------------------------------------------
install_deps
apt_update

install_proton_vpn
install_proton_mail_desktop
install_proton_mail_bridge
install_proton_pass
install_proton_authenticator

# --------------------------------------------------
# Category marker (for master.sh)
# --------------------------------------------------
touch "$STATE_DIR/security"

echo "=================================================="
echo " Proton Suite Installation COMPLETE"
echo " Installed markers:"
ls -1 "$STATE_DIR" | grep proton || true
echo "=================================================="
