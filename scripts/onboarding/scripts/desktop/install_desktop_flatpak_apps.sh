#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"

mkdir -p "$LOG_DIR" "$STATE_DIR"
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
  sudo apt-get install -y flatpak
fi

if ! flatpak remote-list | awk '{print $1}' | grep -qx flathub; then
  echo "Adding Flathub remote..."
  sudo flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo
fi

# --------------------------------------------------
# Desktop Flatpak applications
# --------------------------------------------------
FLATPAK_APPS=(
  org.gnome.Timeshift
  org.yubico.YubiKeyManager
  org.yubico.yubioath
  org.flameshot.Flameshot
  org.cryptomator.Cryptomator
  com.github.zocker_160.SyncThingy
)

echo ""
echo "Installing Flatpak desktop applications..."

for app in "${FLATPAK_APPS[@]}"; do
  if flatpak list --app | awk '{print $1}' | grep -qx "$app"; then
    echo "✔ $app already installed"
  else
    echo "➕ Installing $app..."
    flatpak install -y flathub "$app"
  fi
done

touch "$STATE_DIR/desktop_flatpak"

echo ""
echo "=================================================="
echo " Desktop Flatpak Apps Installation Complete"
echo "=================================================="
