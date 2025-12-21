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

# Standardized source: official Neovim release tarball
# Default channel/tag: "stable"
NEOVIM_TAG="${NEOVIM_TAG:-stable}"
NEOVIM_URL="https://github.com/neovim/neovim/releases/download/${NEOVIM_TAG}/nvim-linux64.tar.gz"

INSTALL_ROOT="/opt/neovim"
INSTALL_DIR="${INSTALL_ROOT}/nvim-linux64"
SYMLINK="/usr/local/bin/nvim"

echo "Neovim tag: ${NEOVIM_TAG}"
echo "Download: ${NEOVIM_URL}"
echo "Install dir: ${INSTALL_DIR}"
echo "Symlink: ${SYMLINK}"

echo "Ensuring dependencies..."
sudo apt-get update
sudo apt-get install -y curl tar

# If already installed via our managed path, show version and optionally refresh
if [ -x "${INSTALL_DIR}/bin/nvim" ]; then
  echo "Neovim appears installed at ${INSTALL_DIR}/bin/nvim"
  "${INSTALL_DIR}/bin/nvim" --version | head -n 2 || true
  echo "Refreshing installation (reinstall) to ensure standardized source is current..."
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Downloading Neovim..."
curl -fL "$NEOVIM_URL" -o "${TMP_DIR}/nvim-linux64.tar.gz"

echo "Extracting..."
tar -xzf "${TMP_DIR}/nvim-linux64.tar.gz" -C "$TMP_DIR"

echo "Installing to ${INSTALL_ROOT}..."
sudo mkdir -p "$INSTALL_ROOT"
sudo rm -rf "$INSTALL_DIR"
sudo mv "${TMP_DIR}/nvim-linux64" "$INSTALL_DIR"

echo "Updating symlink ${SYMLINK}..."
sudo ln -sf "${INSTALL_DIR}/bin/nvim" "$SYMLINK"

echo "Neovim installed:"
command -v nvim
nvim --version | head -n 2 || true
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/<category>"

echo "Done."

