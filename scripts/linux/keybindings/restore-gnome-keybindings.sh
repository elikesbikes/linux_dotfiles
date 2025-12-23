#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BACKUP_DIR="${SCRIPT_DIR}/backups/current"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "ERROR: Backup directory not found:"
  echo "  $BACKUP_DIR"
  exit 1
fi

echo
echo "GNOME Keybindings Restore"
echo "Using backup from:"
echo "  $BACKUP_DIR"
echo

echo "Select restore mode:"
echo "  1) Restore ONLY custom keybindings"
echo "  2) Restore ALL keybindings (system + custom)"
echo "  3) Restore ALL keybindings + FULL GNOME config"
echo "  4) Restore ONLY dock configuration"
echo
read -p "Enter choice [1-4]: " MODE

echo
read -p "This will overwrite current settings. Continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Restore aborted."
  exit 0
fi

restore_system_keybindings() {
  local file="$1"
  [ -f "$file" ] || return
  while read -r schema key value; do
    [[ -z "$schema" || -z "$key" || -z "$value" ]] && continue
    gsettings set "$schema" "$key" "$value" 2>/dev/null || true
  done < <(sed -E 's/^(org\.gnome\.[^ ]+) ([^ ]+) (.+)$/\1 \2 \3/' "$file")
}

restore_custom_keybindings() {
  local file="$1"

  # Rebuild custom-keybindings index (critical)
  gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
  "[
  $(grep '^\[' "$file" \
    | sed 's/\[//;s/\]//' \
    | sed 's|^|'\''/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/|;s|$|/'\''' \
    | paste -sd, -)
  ]"

  dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ \
    < "$file"
}

restore_dock() {
  local file="$1"
  [ -f "$file" ] || return
  dconf load /org/gnome/shell/extensions/dash-to-dock/ < "$file"
}

case "$MODE" in
  1)
    echo "Restoring custom keybindings only..."
    restore_custom_keybindings "$BACKUP_DIR/custom-keybindings.dconf"
    ;;
  2)
    echo "Restoring all keybindings..."
    restore_system_keybindings "$BACKUP_DIR/wm-keybindings.txt"
    restore_system_keybindings "$BACKUP_DIR/media-keys.txt"
    restore_system_keybindings "$BACKUP_DIR/shell-keybindings.txt"
    restore_system_keybindings "$BACKUP_DIR/mutter-keybindings.txt"
    restore_custom_keybindings "$BACKUP_DIR/custom-keybindings.dconf"
    ;;
  3)
    echo "Restoring all keybindings + full GNOME config..."
    restore_system_keybindings "$BACKUP_DIR/wm-keybindings.txt"
    restore_system_keybindings "$BACKUP_DIR/media-keys.txt"
    restore_system_keybindings "$BACKUP_DIR/shell-keybindings.txt"
    restore_system_keybindings "$BACKUP_DIR/mutter-keybindings.txt"
    restore_custom_keybindings "$BACKUP_DIR/custom-keybindings.dconf"
    dconf load / < "$BACKUP_DIR/full-gnome-backup.conf"
    ;;
  4)
    echo "Restoring dock configuration only..."
    restore_dock "$BACKUP_DIR/dock-dash-to-dock.dconf"
    ;;
  *)
    echo "Invalid selection."
    exit 1
    ;;
esac

echo
echo "Restore complete."
echo "Log out and log back in for all changes to take effect."
