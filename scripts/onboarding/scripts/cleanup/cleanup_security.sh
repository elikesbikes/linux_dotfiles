#!/usr/bin/env bash
set -euo pipefail

echo "This will REMOVE Proton & security tools."
read -rp "Continue? (yes/no): " ans
[[ "$ans" == "yes" ]] || exit 0

sudo apt remove -y \
  proton-vpn-gnome protonvpn-cli proton-bridge proton-authenticator || true

flatpak uninstall -y me.proton.Pass || true

echo "Security cleanup complete."
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
rm -f "$STATE_DIR/<category>"
