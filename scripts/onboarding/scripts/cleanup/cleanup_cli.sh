#!/usr/bin/env bash
set -euo pipefail

echo "This will REMOVE CLI tools installed by onboarding."
read -rp "Continue? (yes/no): " ans
[[ "$ans" == "yes" ]] || exit 0

sudo apt remove -y exa fastfetch stow zoxide direnv figlet || true
sudo snap remove yazi || true

sudo rm -f /usr/local/bin/starship
sudo rm -f /usr/local/bin/nvim
sudo rm -rf /opt/neovim

echo "CLI cleanup complete."

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
rm -f "$STATE_DIR/<category>"
