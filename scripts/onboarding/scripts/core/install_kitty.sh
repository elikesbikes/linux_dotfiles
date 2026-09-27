#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_kitty.sh
# Version: 1.1.0
#
# Versioning:
# 1.1.0 - Also install imagemagick: it's Kitty's own optional dependency for
#         `kitten icat` (confirmed via `pacman -Qi kitty` on Arch: "Optional
#         Deps: imagemagick: viewing images with icat"). Without it, `kitten
#         icat` — and anything that shells out to it, like fastfetch's
#         kitty-icat logo type — silently fails to render certain image
#         formats. Previously only installed defensively inside
#         cli/install_fastfetch.sh; belongs here since it's a kitty concern,
#         not a fastfetch one.
# 1.0.0 - Initial implementation:
#         - State-based idempotency via XDG state marker
#         - Install kitty terminal via apt
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.1.0"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/kitty"

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# State-based idempotency check (authoritative)
# --------------------------------------------------
if [[ -f "$STATE_FILE" ]]; then
  echo "STATE: kitty already marked as installed ($STATE_FILE)"
  if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    echo "imagemagick already installed."
    echo "Nothing to do. Exiting."
    exit 0
  fi
  echo "imagemagick missing (older install predates this dependency) — installing it now."
  sudo apt-get update
  sudo apt-get install -y imagemagick
  exit 0
fi

# --------------------------------------------------
# Binary presence check (defensive)
# --------------------------------------------------
if command -v kitty >/dev/null 2>&1; then
  echo "kitty already installed: $(command -v kitty)"
  kitty --version || true
  if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
    echo "Installing imagemagick (kitty's optional dependency for kitten icat)..."
    sudo apt-get update
    sudo apt-get install -y imagemagick
  else
    echo "imagemagick already installed."
  fi
  echo "Marking as installed."
  touch "$STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# Installation
# --------------------------------------------------
echo "Installing kitty via apt..."

sudo apt-get update
# kitty-terminfo ships the xterm-kitty terminfo entry so remote/SSH sessions
# launched from a Kitty terminal don't fail with "unknown terminal type".
# imagemagick is kitty's own optional dependency for `kitten icat`.
sudo apt-get install -y kitty kitty-terminfo imagemagick

# --------------------------------------------------
# Post-install validation
# --------------------------------------------------
if command -v kitty >/dev/null 2>&1; then
  echo "SUCCESS: kitty installed: $(command -v kitty)"
  kitty --version || true
  touch "$STATE_FILE"
else
  echo "FAIL: kitty not found after install"
  exit 1
fi

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
