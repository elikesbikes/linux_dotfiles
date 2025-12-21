#!/usr/bin/env bash
set -euo pipefail

echo "This will REMOVE desktop applications."
read -rp "Continue? (yes/no): " ans
[[ "$ans" == "yes" ]] || exit 0

flatpak uninstall -y \
  de.leopoldluley.Clapgrep \
  org.cryptomator.Cryptomator \
  net.nokyan.Resources \
  md.obsidian.Obsidian \
  com.github.zocker_160.SyncThingy \
  com.rustdesk.RustDesk \
  com.vysp3r.ProtonPlus \
  com.yubico.yubioath \
  io.github.flattool.Warehouse \
  io.github.sigmasd.stimulator \
  org.libretro.RetroArch \
  app.bluebubbles.BlueBubbles || true

sudo apt remove -y \
  timeshift yubikey-manager-qt flameshot caffeine kitty || true

echo "Desktop cleanup complete."
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
rm -f "$STATE_DIR/<category>"
