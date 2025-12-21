#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="/home/ecloaiza/devops/github/linux_dotfiles"
DOTFILES_REPO="https://github.com/elikesbikes/linux_dotfiles"
MASTER_SCRIPT="$DOTFILES_DIR/scripts/onboarding/master.sh"

echo "=================================================="
echo " Linux Dotfiles Bootstrap (FORCE MODE)"
echo "=================================================="
echo ""
echo "Target directory:"
echo "  $DOTFILES_DIR"
echo ""

# --------------------------------------------------
# Ensure git exists
# --------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "Installing git..."
  sudo apt-get update
  sudo apt-get install -y git
fi

# --------------------------------------------------
# Force remove existing repo
# --------------------------------------------------
if [[ -d "$DOTFILES_DIR" ]]; then
  echo "Existing dotfiles directory found."
  echo "Removing it completely..."
  rm -rf "$DOTFILES_DIR"
fi

# --------------------------------------------------
# Fresh clone
# --------------------------------------------------
echo "Cloning dotfiles repository..."
mkdir -p "$(dirname "$DOTFILES_DIR")"
git clone "$DOTFILES_REPO" "$DOTFILES_DIR"

# --------------------------------------------------
# Launch onboarding master script
# --------------------------------------------------
if [[ ! -f "$MASTER_SCRIPT" ]]; then
  echo "ERROR: master.sh not found at:"
  echo "  $MASTER_SCRIPT"
  exit 1
fi

chmod +x "$MASTER_SCRIPT"

echo ""
echo "=================================================="
echo " Launching onboarding master script"
echo "=================================================="
echo ""

exec "$MASTER_SCRIPT"
