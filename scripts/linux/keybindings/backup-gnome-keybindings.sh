#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Backup root
BACKUP_ROOT="${SCRIPT_DIR}/backups"
mkdir -p "$BACKUP_ROOT"

# Timestamp
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
BACKUP_DIR="${BACKUP_ROOT}/gnome-keybindings-${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

echo "Saving GNOME keybindings backup to:"
echo "  $BACKUP_DIR"
echo

# -------------------------------
# System / built-in keybindings
# -------------------------------
gsettings list-recursively org.gnome.desktop.wm.keybindings \
  > "$BACKUP_DIR/wm-keybindings.txt"

gsettings list-recursively org.gnome.settings-daemon.plugins.media-keys \
  > "$BACKUP_DIR/media-keys.txt"

gsettings list-recursively org.gnome.shell.keybindings \
  > "$BACKUP_DIR/shell-keybindings.txt"

gsettings list-recursively org.gnome.mutter.keybindings \
  > "$BACKUP_DIR/mutter-keybindings.txt"

# -------------------------------
# Custom shortcuts (CORRECT WAY)
# -------------------------------
dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ \
  > "$BACKUP_DIR/custom-keybindings.dconf"

# -------------------------------
# Optional: full GNOME backup
# -------------------------------
dconf dump / > "$BACKUP_DIR/full-gnome-backup.conf"

echo
echo "Backup complete."
echo "Files created:"
ls -1 "$BACKUP_DIR"
