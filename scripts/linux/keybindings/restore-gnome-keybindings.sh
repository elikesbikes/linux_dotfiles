#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 /path/to/backup-directory"
  exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "Error: Backup directory does not exist:"
  echo "  $BACKUP_DIR"
  exit 1
fi

echo
echo "GNOME Keybindings Restore"
echo "Backup source:"
echo "  $BACKUP_DIR"
echo

echo "Select restore mode:"
echo "  1) Restore ONLY custom keybindings"
echo "  2) Restore ALL keybindings (system + custom)"
echo "  3) Restore ALL keybindings + FULL GNOME config"
echo
read -p "Enter choice [1-3]: " MODE

echo
read -p "This will overwrite current settings. Continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Restore aborted."
  exit 0
fi

restore_system_keybindings() {
  local file="$1"
  if [ -f "$file" ]; then
    while read -r schema key value; do
      [[ -z "$schema" || -z "$key" || -z "$value" ]] && continue
      gsettings set "$schema" "$key" "$value" 2>/dev/null || true
    done < <(sed -E 's/^(org\.gnome\.[^ ]+) ([^ ]+) (.+)$/\1 \2 \3/' "$file")
  fi
}

restore_custom_keybindings() {
  local file="$1"
  if [ -f "$file" ]; then
    echo "Restoring custom keybindings..."
    dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ \
      < "$file"
  else
    echo "Warning: custom-keybindings.dconf not found"
  fi
}

case "$MODE" in
  1)
    echo "Mode: Custom keybindings ONLY"
    restore_custom_keybindings "$BACKUP_DIR/custom-keybindings.dconf"
    ;;

  2)
    echo "Mode: All keybindings (system + custom)"

    restore_system_keybindings "$BACKUP_DIR/wm-keybindings.txt"
    restore_system_keybindings "$BACKUP_DIR/media-keys.txt"
    restore_system_keybindings "$BACKUP_DIR/shell-keybindings.txt"
    restore_system_keybindings "$BACKUP_DIR/mutter-keybindings.txt"

    restore_custom_keybindings "$BACKUP_DIR/custom-keybindings.dconf"
    ;;

  3)
    echo "Mode: All keybindings + FULL GNOME config"

    restore_system_keybindings "$BACKUP_DIR/wm-keybindings.txt"
    restore_system_keybindings "$BACKUP_DIR/media-keys.txt"
    restore_system_keybindings "$BACKUP_DIR/shell-keybindings.txt"
    restore_system_keybindings "$BACKUP_DIR/mutter-keybindings.txt"

    restore_custom_keybindings "$BACKUP_DIR/custom-keybindings.dconf"

    if [ -f "$BACKUP_DIR/full-gnome-backup.conf" ]; then
      echo "Restoring full GNOME config..."
      dconf load / < "$BACKUP_DIR/full-gnome-backup.conf"
    else
      echo "Warning: full-gnome-backup.conf not found"
    fi
    ;;

  *)
    echo "Invalid selection."
    exit 1
    ;;
esac

echo
echo "Restore complete."
echo "Log out and log back in for all changes to take effect."
