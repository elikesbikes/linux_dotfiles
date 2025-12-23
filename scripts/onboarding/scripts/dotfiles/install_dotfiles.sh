#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Linux Dotfiles Bootstrap (FORCE OVERWRITE + STOW)
# ==================================================

# --------------------------------------------------
# Hard safety rule:
# Never operate from inside the repo we may delete
# --------------------------------------------------
cd "$HOME"

TARGET_DIR="$HOME/devops/github/linux_dotfiles"
REPO_URL="https://github.com/elikesbikes/linux_dotfiles"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/install_dotfiles.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo " Linux Dotfiles Bootstrap (FORCE OVERWRITE + STOW)"
echo "=================================================="
echo
echo "Target directory:"
echo "  $TARGET_DIR"
echo

# --------------------------------------------------
# Ensure required tools
# --------------------------------------------------
echo "Ensuring required tools..."
sudo apt-get update -y
sudo apt-get install -y git stow

# --------------------------------------------------
# Remove existing repo (safe now)
# --------------------------------------------------
if [[ -d "$TARGET_DIR" ]]; then
  echo
  echo "Existing dotfiles directory found."
  echo "Removing it completely..."
  rm -rf "$TARGET_DIR"
fi

# --------------------------------------------------
# Clone fresh repo
# --------------------------------------------------
echo
echo "Cloning dotfiles repository..."
git clone "$REPO_URL" "$TARGET_DIR"

# --------------------------------------------------
# Pre-stow conflict cleanup
# --------------------------------------------------
echo
echo "Preparing for stow..."

if [[ -d "$HOME/.local/share/omakub/defaults/bash" ]]; then
  echo "Detected Omakub bash defaults:"
  echo "  ~/.local/share/omakub/defaults/bash"
  echo "Removing to avoid stow conflicts..."
  rm -rf "$HOME/.local/share/omakub/defaults/bash"
fi

if [[ -f "$HOME/.bashrc" ]]; then
  echo "Removing existing ~/.bashrc to allow stow-managed version..."
  rm -f "$HOME/.bashrc"
fi

# --------------------------------------------------
# Run stow
# --------------------------------------------------
echo
echo "Running stow..."
cd "$TARGET_DIR"
stow . -t ~

# --------------------------------------------------
# Launch onboarding master
# --------------------------------------------------
MASTER="$TARGET_DIR/scripts/onboarding/scripts/master/master.sh"

echo
echo "=================================================="
echo " Dotfiles deployed successfully"
echo " Launching onboarding master script"
echo "=================================================="
echo

exec "$MASTER"
