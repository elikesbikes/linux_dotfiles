#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/verify_desktop.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VERIFY DESKTOP ==="

fail=0

flatpaks=(
  de.leopoldluley.Clapgrep
  org.cryptomator.Cryptomator
  net.nokyan.Resources
  md.obsidian.Obsidian
  com.github.zocker_160.SyncThingy
  com.rustdesk.RustDesk
  com.vysp3r.ProtonPlus
  com.yubico.yubioath
  io.github.flattool.Warehouse
  io.github.sigmasd.stimulator
  org.libretro.RetroArch
  app.bluebubbles.BlueBubbles
)

for app in "${flatpaks[@]}"; do
  if flatpak list --app | awk '{print $1}' | grep -qx "$app"; then
    echo "OK: $app"
  else
    echo "FAIL: $app missing"
    fail=1
  fi
done

native_pkgs=(
  timeshift
  yubikey-manager-qt
  flameshot
  caffeine
  kitty
)

for pkg in "${native_pkgs[@]}"; do
  if dpkg -l | awk '{print $2}' | grep -qx "$pkg"; then
    echo "OK: $pkg"
  else
    echo "FAIL: $pkg missing"
    fail=1
  fi
done

exit $fail
