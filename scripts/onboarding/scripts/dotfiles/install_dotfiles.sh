#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="https://github.com/elikesbikes/linux_dotfiles"
DOTFILES_DIR="$HOME/devops/github/linux_dotfiles"
MASTER_SCRIPT="$DOTFILES_DIR/scripts/onboarding/scripts/master/master.sh"

echo "=================================================="
echo " Linux Dotfiles Bootstrap (FORCE OVERWRITE + STOW)"
echo "=================================================="
echo
echo "Target directory:"
echo "  $DOTFILES_DIR"
echo

# --------------------------------------------------
# Always move to a safe directory first
# --------------------------------------------------
cd "$HOME"

# --------------------------------------------------
# Ensure required base tools
# --------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "Installing git..."
  sudo apt-get update
  sudo apt-get install -y git
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "Installing stow..."
  sudo apt-get update
  sudo apt-get install -y stow
fi

# --------------------------------------------------
# Force remove existing dotfiles repo
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
# Remove known conflicting files / directories
# --------------------------------------------------

# Remove Omakub bash defaults (conflict with stow)
OMAKUB_BASH_DIR="$HOME/.local/share/omakub/defaults/bash"
if [[ -d "$OMAKUB_BASH_DIR" ]]; then
  echo "Detected Omakub bash defaults:"
  echo "  $OMAKUB_BASH_DIR"
  echo "Removing to avoid stow conflicts..."
  rm -rf "$OMAKUB_BASH_DIR"
fi

# Remove existing ~/.bashrc (managed by stow)
if [[ -f "$HOME/.bashrc" || -L "$HOME/.bashrc" ]]; then
  echo "Removing existing ~/.bashrc to allow stow-managed version..."
  rm -f "$HOME/.bashrc"
fi

# --------------------------------------------------
# Run stow
# --------------------------------------------------
echo
echo "Running stow..."
cd "$DOTFILES_DIR"

set +e
stow . -t ~
STOW_EXIT_CODE=$?
set -e

if [[ "$STOW_EXIT_CODE" -ne 0 ]]; then
  echo
  echo "=================================================="
  echo " Stow reported conflicts."
  echo
  echo "Resolve remaining conflicts, then re-run:"
  echo
  echo "  cd $DOTFILES_DIR"
  echo "  stow . -t ~"
  echo "=================================================="
  exit 1
fi

# --------------------------------------------------
# Launch onboarding master script
# --------------------------------------------------
if [[ ! -x "$MASTER_SCRIPT" ]]; then
  echo "ERROR: master.sh not found or not executable:"
  echo "  $MASTER_SCRIPT"
  exit 1
fi

echo
echo "=================================================="
echo " Dotfiles deployed successfully"
echo " Launching onboarding master script"
echo "=================================================="
echo

cd "$HOME"
exec "$MASTER_SCRIPT"
