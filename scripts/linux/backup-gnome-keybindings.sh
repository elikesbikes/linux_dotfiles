#!/usr/bin/env bash

# Create timestamp
timestamp=$(date +"%Y%m%d_%H%M%S")

# Destination directory
backup_dir="$HOME/Downloads/gnome-keybindings-$timestamp"
mkdir -p "$backup_dir"

echo "Saving GNOME keybindings backup to: $backup_dir"

# Export keybindings from major GNOME schemas
gsettings list-recursively org.gnome.desktop.wm.keybindings >"$backup_dir/wm-keybindings.txt"
gsettings list-recursively org.gnome.settings-daemon.plugins.media-keys >"$backup_dir/media-keys.txt"
gsettings list-recursively org.gnome.shell.keybindings >"$backup_dir/shell-keybindings.txt"
gsettings list-recursively org.gnome.mutter.keybindings >"$backup_dir/mutter-keybindings.txt"
gsettings list-recursively org.gnome.settings-daemon.plugins.media-keys.custom-keybindings >"$backup_dir/custom-shortcuts.txt"

# Create a full GNOME config dump (optional but recommended)
dconf dump / >"$backup_dir/full-gnome-backup.conf"

echo "Backup complete!"
echo "Files saved under: $backup_dir"
