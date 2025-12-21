#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
mkdir -p "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Installing Desktop Native Apps"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Native desktop packages
# --------------------------------------------------
PACKAGES=(
  timeshift
  yubikey-manager-qt
  flameshot
  caffeine
  kitty
)

echo "Updating apt..."
sudo apt-get update

echo ""
echo "Installing native desktop packages..."

for pkg in "${PACKAGES[@]}"; do
  if dpkg -l | awk '{print $2}' | grep -qx "$pkg"; then
    echo "✔ $pkg already installed. Upgrading..."
    sudo apt-get install -y "$pkg"
  else
    echo "➕ Installing $pkg..."
    sudo apt-get install -y "$pkg"
  fi
done
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"



echo ""
echo "=================================================="
echo " Desktop Native Apps Installation Complete"
echo "=================================================="