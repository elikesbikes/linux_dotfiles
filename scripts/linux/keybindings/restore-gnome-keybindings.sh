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
echo "GNOME Restore Utility"
echo "Backup source:"
echo "  $BACKUP_DIR"
echo

echo "What do you want to restore?"
echo "  1) Custom keybindings ONLY"
echo "  2) System keybindings (GNOME defaults)"
echo "  3) Dock configuration (Dash-to-Dock)"
echo "  4) Dock pinned applications (icons/order)"
echo "  5) FULL GNOME configuration"
echo
echo "You may select multiple options (comma-separated)."
echo "Example: 1,3,4"
echo
read -p "Enter selection: " SELECTION

if [ -z "$SELECTION" ]; then
  echo "No selection made. Aborting."
  exit 1
fi

echo
read -p "This will overwrite selected settings. Continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Restore aborted."
  exit 0
fi

# --------------------------------------------------
# Restore helpers
# --------------------------------------------------
restore_system_keybindings() {
  echo "Restoring system keybindings..."
  for file in wm-keybindings.txt media-keys.txt shell-keybindings.txt mutter-keybindings.txt; do
    local path="$BACKUP_DIR/$file"
    [ -f "$path" ] || continue
    while read -r schema key value; do
      [[ -z "$schema" || -z "$key" || -z "$value" ]] && continue
      gsettings set "$schema" "$key" "$value" 2>/dev/null || true
    done < <(sed -E 's/^(org\.gnome\.[^ ]+) ([^ ]+) (.+)$/\1 \2 \3/' "$path")
  done
}

restore_custom_keybindings() {
  local file="$BACKUP_DIR/custom-keybindings.dconf"
  [ -f "$file" ] || { echo "Custom keybindings backup not found."; return; }

  echo "Restoring custom keybindings..."

  # Rebuild the index list (CRITICAL)
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

restore_dock_config() {
  local file="$BACKUP_DIR/dock-dash-to-dock.dconf"
  [ -f "$file" ] || { echo "Dock configuration backup not found."; return; }

  echo "Restoring dock configuration..."
  dconf load /org/gnome/shell/extensions/dash-to-dock/ < "$file"
}

restore_dock_favorites() {
  local file="$BACKUP_DIR/dock-favorite-apps.txt"
  [ -f "$file" ] || { echo "Dock favorites backup not found."; return; }

  echo "Restoring dock pinned applications..."
  gsettings set org.gnome.shell favorite-apps "$(cat "$file")"
}

restore_full_gnome() {
  local file="$BACKUP_DIR/full-gnome-backup.conf"
  [ -f "$file" ] || { echo "Full GNOME backup not found."; return; }

  echo "Restoring FULL GNOME configuration..."
  dconf load / < "$file"
}

# --------------------------------------------------
# Execute selections
# --------------------------------------------------
IFS=',' read -ra OPTIONS <<< "$SELECTION"

for opt in "${OPTIONS[@]}"; do
  case "$(echo "$opt" | xargs)" in
    1) restore_custom_keybindings ;;
    2) restore_system_keybindings ;;
    3) restore_dock_config ;;
    4) restore_dock_favorites ;;
    5) restore_full_gnome ;;
    *)
      echo "Invalid option: $opt"
      exit 1
      ;;
  esac
done

echo
echo "Restore complete."
echo "Log out and log back in for all changes to take effect."
