#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

echo "Standardized source: official Starship installer (installs to /usr/local/bin)."

echo "Ensuring curl is present..."
sudo apt-get update
sudo apt-get install -y curl

if command -v starship >/dev/null 2>&1; then
  echo "starship already installed: $(command -v starship)"
  starship --version || true
  echo "Reinstalling via official installer to standardize location (safe overwrite)..."
fi

# -y: no prompts
# --bin-dir: enforce /usr/local/bin
curl -fsSL https://starship.rs/install.sh | sh -s -- -y --bin-dir /usr/local/bin
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"


echo "starship installed:"
command -v starship


echo "Done."
