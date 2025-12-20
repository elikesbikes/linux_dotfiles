#!/usr/bin/env bash

if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/backup-directory"
  exit 1
fi

backup_dir="$1"

if [ ! -d "$backup_dir" ]; then
  echo "Error: Directory '$backup_dir' does not exist."
  exit 1
fi

echo "This will restore GNOME keybindings from: $backup_dir"
read -p "Are you sure you want to overwrite current settings? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "Restore aborted."
  exit 0
fi

read -p "Do you want to restore the full GNOME config as well? (yes/no): " full_restore

echo "Restoring keybindings..."

restore_keybindings() {
  local file=$1
  if [ -f "$file" ]; then
    while read -r schema key value; do
      if [[ -z "$schema" || -z "$key" || -z "$value" ]]; then
        continue
      fi
      gsettings set "$schema" "$key" "$value" 2>/dev/null
    done < <(sed -E "s/^(org\.gnome\.[^ ]+) ([^ ]+) (.+)$/\1 \2 \3/" "$file")
  else
    echo "Warning: $(basename "$file") not found"
  fi
}

restore_keybindings "$backup_dir/wm-keybindings.txt"
restore_keybindings "$backup_dir/media-keys.txt"
restore_keybindings "$backup_dir/shell-keybindings.txt"
restore_keybindings "$backup_dir/mutter-keybindings.txt"
restore_keybindings "$backup_dir/custom-shortcuts.txt"

if [[ "$full_restore" == "yes" ]]; then
  if [ -f "$backup_dir/full-gnome-backup.conf" ]; then
    echo "Restoring full GNOME config via dconf load..."
    dconf load / < "$backup_dir/full-gnome-backup.conf"
  else
    echo "Warning: full-gnome-backup.conf not found"
  fi
fi

echo "Restore complete. You may need to log out and log back in for all changes to take effect."
