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
# Flatpak apps ONLY
# --------------------------------------------------
FLATPAK_APPS=(
  org.gnome.Timeshift
  org.yubico.YubiKeyManager
  org.yubico.yubioath
  org.flameshot.Flameshot
  org.cryptomator.Cryptomator
  com.github.zocker_160.SyncThingy
)

for app in "${FLATPAK_APPS[@]}"; do
  if flatpak info "$app" >/dev/null 2>&1; then
    echo "✔ $app already installed."
  else
    echo "➕ Installing $app..."
    flatpak install -y flathub "$app"
  fi
done

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/desktop-flatpak"

echo ""
echo "=================================================="
echo " Desktop Flatpak Apps Installation Complete"
echo "=================================================="
