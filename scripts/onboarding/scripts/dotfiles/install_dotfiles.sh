#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"

mkdir -p "$LOG_DIR" "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Dotfiles bootstrap"
echo "Date: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

DOTFILES_DIR="/home/ecloaiza/DevOps/GitHub/linux_dotfiles"
DOTFILES_REPO="https://github.com/elikesbikes/linux_dotfiles"

# --------------------------------------------------
# Ensure prerequisites
# --------------------------------------------------
echo "Ensuring git is installed..."
if ! command -v git >/dev/null 2>&1; then
  echo "Installing git..."
  sudo apt-get update
  sudo apt-get install -y git
else
  git --version
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
# Deployment notice (non-destructive)
# --------------------------------------------------
echo ""
echo "Dotfiles repository is present at:"
echo "  $DOTFILES_DIR"
echo ""
echo "No dotfiles have been deployed yet."
echo ""
echo "Next steps (manual, intentional):"
echo "  cd $DOTFILES_DIR"
echo "  stow <package>"
echo ""
echo "This avoids accidental overwrites."

# --------------------------------------------------
# Mark state
# --------------------------------------------------
touch "$STATE_DIR/dotfiles"

echo ""
echo "=================================================="
echo " Dotfiles bootstrap complete"
echo "=================================================="
