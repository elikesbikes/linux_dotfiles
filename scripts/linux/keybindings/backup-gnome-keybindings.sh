#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fixed backup directory
BACKUP_DIR="${SCRIPT_DIR}/backups/current"
mkdir -p "$BACKUP_DIR"

echo "Saving GNOME configuration backup to:"
echo "  $BACKUP_DIR"
echo

# Clean previous backup contents
rm -f "$BACKUP_DIR"/*

# --------------------------------------------------
# System / built-in keybindings
# --------------------------------------------------
gsettings list-recursively org.gnome.desktop.wm.keybindings \
  > "$BACKUP_DIR/wm-keybindings.txt"

gsettings list-recursively org.gnome.settings-daemon.plugins.media-keys \
  > "$BACKUP_DIR/media-keys.txt"

gsettings list-recursively org.gnome.shell.keybindings \
  > "$BACKUP_DIR/shell-keybindings.txt"

gsettings list-recursively org.gnome.mutter.keybindings \
  > "$BACKUP_DIR/mutter-keybindings.txt"

# --------------------------------------------------
# Custom keybindings (GNOME-correct)
# --------------------------------------------------
dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ \
  > "$BACKUP_DIR/custom-keybindings.dconf"

# --------------------------------------------------
# Dock configuration (Dash-to-Dock / Ubuntu Dock)
# --------------------------------------------------
dconf dump /org/gnome/shell/extensions/dash-to-dock/ \
  > "$BACKUP_DIR/dock-dash-to-dock.dconf"

# --------------------------------------------------
# Optional: full GNOME configuration backup
# --------------------------------------------------
dconf dump / > "$BACKUP_DIR/full-gnome-backup.conf"

echo
echo "Backup complete."
echo "Files saved:"
ls -1 "$BACKUP_DIR"
