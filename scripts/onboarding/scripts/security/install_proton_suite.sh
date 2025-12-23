#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"

mkdir -p "$LOG_DIR" "$STATE_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Installing Proton Security Suite"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# 1. Ensure Flatpak (needed for Proton Pass only)
# --------------------------------------------------
if ! command -v flatpak >/dev/null 2>&1; then
  echo "Installing Flatpak..."
  sudo apt-get update
  sudo apt-get install -y flatpak gnome-software-plugin-flatpak
fi

if ! flatpak remote-list | awk '{print $1}' | grep -qx flathub; then
  echo "Adding Flathub remote..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# --------------------------------------------------
# 2. Proton VPN official repository (APT)
# --------------------------------------------------
if ! apt-cache policy | grep -q repo.protonvpn.com; then
  echo "Setting up Proton VPN repository..."
  TMP_DEB="$(mktemp)"
  wget -q -O "$TMP_DEB" \
    https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.4_all.deb
  sudo dpkg -i "$TMP_DEB"
  rm -f "$TMP_DEB"
fi

sudo apt-get update

# --------------------------------------------------
# 3. Install Proton VPN + Bridge (native)
# --------------------------------------------------
echo "Installing Proton VPN and Proton Bridge..."

sudo apt-get install -y \
  #proton-mail \
  protonvpn-pass \
  protonmail-bridge

# --------------------------------------------------
# 4. Install Proton Mail (official .deb)
# --------------------------------------------------
if ! dpkg -l | awk '{print $2}' | grep -qx proton-mail; then
  echo "Installing Proton Mail (official .deb)..."
  TMP_DEB="$(mktemp)"
  wget -q -O "$TMP_DEB" \
    https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb
  sudo apt-get install -y "$TMP_DEB"
  rm -f "$TMP_DEB"
else
  echo "✔ Proton Mail already installed"
fi

# --------------------------------------------------
# 5. Install Proton Pass (Flatpak)
# --------------------------------------------------
if ! flatpak list --app | awk '{print $1}' | grep -qx me.proton.Pass; then
  echo "Installing Proton Pass (Flatpak)..."
  flatpak install -y flathub me.proton.Pass
else
  echo "✔ Proton Pass already installed"
fi

touch "$STATE_DIR/security"

echo ""
echo "=================================================="
echo " Proton Security Suite Installation Complete"
echo "=================================================="
echo "NOTE: You may need to log out and back in for VPN tray icons."
