#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Starting Proton Suite Installation"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Sanity checks
# --------------------------------------------------
if ! command -v apt >/dev/null 2>&1; then
  echo "ERROR: apt is required (Ubuntu/Debian only)."
  exit 1
fi

echo "Detected apt-based system."

# --------------------------------------------------
# Core dependencies
# --------------------------------------------------
echo ""
echo "Installing required base dependencies..."
sudo apt-get update
sudo apt-get install -y \
  wget \
  curl \
  gnupg \
  ca-certificates \
  flatpak \
  gnome-software-plugin-flatpak

# Ensure flathub exists (idempotent)
if ! flatpak remotes | awk '{print $1}' | grep -qx flathub; then
  echo "Adding Flathub remote..."
  flatpak remote-add --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo
else
  echo "Flathub already configured."
fi

# --------------------------------------------------
# Proton VPN repository (official)
# --------------------------------------------------
echo ""
echo "Configuring Proton VPN official repository..."

PROTON_REPO_DEB="/tmp/protonvpn-stable-release.deb"
PROTON_REPO_URL="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.4_all.deb"

if ! apt-cache policy | grep -q "repo.protonvpn.com"; then
  echo "Proton VPN repo not found. Installing..."
  wget -q -O "$PROTON_REPO_DEB" "$PROTON_REPO_URL"
  sudo dpkg -i "$PROTON_REPO_DEB"
  rm -f "$PROTON_REPO_DEB"
  sudo apt-get update
else
  echo "Proton VPN repository already present."
fi

# --------------------------------------------------
# Proton VPN + Bridge (native)
# --------------------------------------------------
echo ""
echo "Installing Proton VPN and Proton Bridge (native)..."

sudo apt-get install -y \
  proton-vpn-gnome \
  protonvpn-cli \
  proton-bridge

echo "Proton VPN version:"
protonvpn-cli --version || true

echo "Proton Bridge installed:"
command -v proton-bridge || true

# --------------------------------------------------
# Proton Mail Desktop (official .deb)
# --------------------------------------------------
echo ""
echo "Installing Proton Mail Desktop (official .deb)..."

if command -v proton-mail >/dev/null 2>&1; then
  echo "Proton Mail already installed."
else
  PROTON_MAIL_DEB="/tmp/proton-mail.deb"
  PROTON_MAIL_URL="https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb"

  echo "Downloading Proton Mail..."
  wget -O "$PROTON_MAIL_DEB" "$PROTON_MAIL_URL"

  echo "Installing Proton Mail..."
  sudo apt-get install -y "$PROTON_MAIL_DEB"

  rm -f "$PROTON_MAIL_DEB"
fi

# --------------------------------------------------
# Proton Pass (Flatpak – REQUIRED)
# --------------------------------------------------
echo ""
echo "Installing Proton Pass (Flatpak – REQUIRED)..."

if flatpak list --app | awk '{print $1}' | grep -qx me.proton.Pass; then
  echo "Proton Pass already installed (Flatpak). Updating..."
  flatpak update -y me.proton.Pass
else
  echo "Installing Proton Pass from Flathub..."
  flatpak install -y flathub me.proton.Pass
fi

# --------------------------------------------------
# Proton Authenticator (native check)
# --------------------------------------------------
echo ""
echo "Ensuring Proton Authenticator is present..."

if dpkg -l | grep -q proton-authenticator; then
  echo "Proton Authenticator already installed."
else
  echo "Installing Proton Authenticator..."
  sudo apt-get install -y proton-authenticator
fi

# --------------------------------------------------
# Final summary
# --------------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"


echo ""
echo "=================================================="
echo " Proton Suite Installation Complete"
echo "=================================================="

echo ""
echo "Installed components:"
echo "- Proton VPN (native)"
echo "- Proton Bridge (native)"
echo "- Proton Mail Desktop (.deb)"
echo "- Proton Pass (Flatpak)"
echo "- Proton Authenticator (native)"

echo ""
echo "NOTE:"
echo "- You may need to log out/in for tray icons to appear."
echo "- Proton VPN kernel integrations may require reboot."
echo ""
echo "Done."

