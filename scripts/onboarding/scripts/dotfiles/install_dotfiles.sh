#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="/home/ecloaiza/devops/github/linux_dotfiles"
DOTFILES_REPO="https://github.com/elikesbikes/linux_dotfiles"
MASTER_SCRIPT="$DOTFILES_DIR/scripts/onboarding/master.sh"

echo "=================================================="
echo " Dotfiles bootstrap"
echo "=================================================="

# --------------------------------------------------
# Ensure git
# --------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "Installing git..."
  sudo apt-get update
  sudo apt-get install -y git
fi

# --------------------------------------------------
# Clone or update repo
# --------------------------------------------------
if [[ -d "$DOTFILES_DIR/.git" ]]; then
  echo "Dotfiles repo already exists. Updating..."
  cd "$DOTFILES_DIR"
  git pull --ff-only
else
  echo "Cloning dotfiles repository..."
  mkdir -p "$(dirname "$DOTFILES_DIR")"
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# --------------------------------------------------
# Launch master onboarding script
# --------------------------------------------------
if [[ ! -x "$MASTER_SCRIPT" ]]; then
  echo "Making master.sh executable..."
  chmod +x "$MASTER_SCRIPT"
fi

echo ""
echo "=================================================="
echo " Launching onboarding master script"
echo "=================================================="
echo ""

exec "$MASTER_SCRIPT"
