#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Installing Desktop Flatpak Apps"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Ensure Flatpak + Flathub
# --------------------------------------------------
if ! command -v flatpak >/dev/null 2>&1; then
  echo "Installing flatpak..."
  sudo apt-get update
  sudo apt-get install -y flatpak gnome-software-plugin-flatpak
fi

if ! flatpak remotes | awk '{print $1}' | grep -qx flathub; then
  echo "Adding Flathub remote..."
  flatpak remote-add --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo
else
  echo "Flathub already configured."
fi

# --------------------------------------------------
# Flatpak applications (authoritative list)
# --------------------------------------------------
APPS=(
  de.leopoldluley.Clapgrep
  org.cryptomator.Cryptomator
  net.nokyan.Resources
  md.obsidian.Obsidian
  com.github.zocker_160.SyncThingy
  com.rustdesk.RustDesk
  com.vysp3r.ProtonPlus
  com.yubico.yubioath
  io.github.flattool.Warehouse
  io.github.sigmasd.stimulator
  org.libretro.RetroArch
  app.bluebubbles.BlueBubbles
)

echo ""
echo "Installing Flatpak applications..."

for app in "${APPS[@]}"; do
  if flatpak list --app | awk '{print $1}' | grep -qx "$app"; then
    echo "✔ $app already installed. Updating..."
    flatpak update -y "$app"
  else
    echo "➕ Installing $app..."
    flatpak install -y flathub "$app"
  fi
done
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

echo ""
echo "=================================================="
echo " Desktop Flatpak Apps Installation Complete"
echo "=================================================="
