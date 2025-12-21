#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Ensuring Flatpak + Flathub"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Flatpak install
# --------------------------------------------------
if command -v flatpak >/dev/null 2>&1; then
  echo "Flatpak already installed: $(flatpak --version)"
else
  echo "Installing Flatpak..."
  sudo apt-get update
  sudo apt-get install -y flatpak gnome-software-plugin-flatpak
fi

# --------------------------------------------------
# Flathub remote
# --------------------------------------------------
if flatpak remotes | awk '{print $1}' | grep -qx flathub; then
  echo "Flathub remote already configured."
else
  echo "Adding Flathub remote..."
  flatpak remote-add --if-not-exists \
    flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

echo ""
echo "Flatpak remotes:"
flatpak remotes
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

echo ""
echo "=================================================="
echo " Flatpak core setup complete"
echo "=================================================="
