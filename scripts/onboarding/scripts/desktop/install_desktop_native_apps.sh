#!/usr/bin/env bash
# shellcheck shell=bash
#
# Helper rules:
# - stdout is DATA ONLY
# - stderr is logs / progress / errors
#
# Policy:
# - Official sources only
# - APT preferred
# - NO SNAP
# - Idempotent (install-once, no rework)

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_BASE/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"
STATE_DIR="$STATE_BASE/installed"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$LOG_DIR" "$STATE_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Installing Desktop Native Apps (APT)"
echo "Policy: Official sources only | NO SNAP"
echo "Date: $(date)"
echo "Log : $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# Native desktop packages (Ubuntu official APT)
# --------------------------------------------------
PACKAGES=(
  timeshift
  kitty
)

echo ""
echo "Checking native desktop packages..."

for pkg in "${PACKAGES[@]}"; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    echo "✔ $pkg already installed — skipping"
  else
    echo "➕ Installing $pkg..."
    sudo apt-get update
    sudo apt-get install -y "$pkg"
  fi
done

# --------------------------------------------------
# Spotify (Official APT Repository)
# Source: https://www.spotify.com/us/download/linux/
# --------------------------------------------------
echo ""
echo "Checking Spotify installation..."

if dpkg -s spotify-client >/dev/null 2>&1; then
  echo "✔ Spotify already installed — skipping"
else
  echo "➕ Installing Spotify (official APT repo)..."

  SPOTIFY_KEYRING="/etc/apt/keyrings/spotify.gpg"
  SPOTIFY_LIST="/etc/apt/sources.list.d/spotify.list"

  sudo install -d -m 0755 /etc/apt/keyrings

  if [ ! -f "$SPOTIFY_KEYRING" ]; then
    curl -fsSL https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg \
      | sudo gpg --dearmor -o "$SPOTIFY_KEYRING"
    sudo chmod 0644 "$SPOTIFY_KEYRING"
  fi

  if [ ! -f "$SPOTIFY_LIST" ]; then
    echo "deb [signed-by=$SPOTIFY_KEYRING] http://repository.spotify.com stable non-free" \
      | sudo tee "$SPOTIFY_LIST" >/dev/null
  fi

  sudo apt-get update
  sudo apt-get install -y spotify-client
fi

# --------------------------------------------------
# RustDesk (Official .deb from GitHub releases)
# --------------------------------------------------
echo ""
echo "Checking RustDesk installation..."

RUSTDESK_PKG="rustdesk"
RUSTDESK_VERSION="1.4.4"
RUSTDESK_DEB="rustdesk-${RUSTDESK_VERSION}-x86_64.deb"
RUSTDESK_URL="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/${RUSTDESK_DEB}"

if dpkg -s "$RUSTDESK_PKG" >/dev/null 2>&1; then
  echo "✔ RustDesk already installed — skipping"
else
  echo "➕ Installing RustDesk ${RUSTDESK_VERSION}..."

  curl -fL "$RUSTDESK_URL" -o "$TMP_DIR/$RUSTDESK_DEB"
  sudo apt-get install -y "$TMP_DIR/$RUSTDESK_DEB"
fi

# --------------------------------------------------
# State marker
# --------------------------------------------------
touch "$STATE_DIR/desktop_native"

echo ""
echo "=================================================="
echo " Desktop Native Apps Installation Complete"
echo "=================================================="
