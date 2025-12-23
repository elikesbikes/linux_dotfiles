#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"

mkdir -p "$LOG_DIR" "$STATE_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Installing Desktop Native Apps (APT)"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Brave Browser (Official Repo)
# --------------------------------------------------
if ! command -v brave-browser >/dev/null 2>&1; then
  echo "Installing Brave Browser (official repo)..."

  sudo apt-get install -y curl gnupg

  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
    https://brave-browser-apt-release.s3.brave.com/ stable main" \
    | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y brave-browser
else
  echo "✔ Brave already installed"
fi

touch "$STATE_DIR/desktop_native"

echo "=================================================="
echo " Desktop Native Apps (APT) Complete"
echo "=================================================="
