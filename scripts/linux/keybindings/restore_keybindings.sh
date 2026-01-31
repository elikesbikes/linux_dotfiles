#!/bin/bash

###############################################################################
# Ubuntu Keybindings and Dock Restore Script
# 
# This script restores:
# - GNOME keybindings (all or custom only)
# - Dock/Dash-to-Dock configuration
# - Favorite applications (dock icons)
#
# Author: ecloaiza
# Created: $(date +%Y-%m-%d)
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Ubuntu Keybindings & Dock Restore Script             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

###############################################################################
# Function to select backup
###############################################################################
select_backup() {
    echo -e "${YELLOW}Available backups:${NC}"
    echo ""
    
    # Check if backup directory exists
    if [ ! -d "${BACKUP_DIR}" ]; then
        echo -e "${RED}Error: No backup directory found at ${BACKUP_DIR}${NC}"
        exit 1
    fi
    
    # List available backups
    local backups=($(ls -1dt "${BACKUP_DIR}"/backup_* 2>/dev/null || true))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}Error: No backups found in ${BACKUP_DIR}${NC}"
        echo ""
        echo "Please run the backup script first:"
        echo "  ./backup_keybindings.sh"
        exit 1
    fi
    
    # Show backups with index
    local i=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_date=$(echo "$backup_name" | sed 's/backup_//' | sed 's/_/ /')
        
        # Check if metadata exists
        if [ -f "$backup/metadata.txt" ]; then
            local ubuntu_version=$(grep "Ubuntu Version:" "$backup/metadata.txt" | cut -d: -f2- | xargs)
            local hostname=$(grep "Hostname:" "$backup/metadata.txt" | cut -d: -f2 | xargs)
            echo -e "${CYAN}[$i]${NC} ${backup_date}"
            echo "    From: $hostname ($ubuntu_version)"
        else
            echo -e "${CYAN}[$i]${NC} ${backup_date}"
        fi
        echo ""
        ((i++))
    done
    
    # Let user select backup
    echo -e -n "${YELLOW}Select backup to restore [1-${#backups[@]}] or 'latest': ${NC}"
    read -r selection
    
    if [ "$selection" = "latest" ] || [ "$selection" = "l" ]; then
        if [ -L "${BACKUP_DIR}/latest" ]; then
            SELECTED_BACKUP=$(readlink -f "${BACKUP_DIR}/latest")
        else
            SELECTED_BACKUP="${backups[0]}"
        fi
    else
        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#backups[@]}" ]; then
            echo -e "${RED}Invalid selection${NC}"
            exit 1
        fi
        SELECTED_BACKUP="${backups[$((selection-1))]}"
    fi
    
    echo ""
    echo -e "${GREEN}Selected backup: $(basename "$SELECTED_BACKUP")${NC}"
    echo ""
}

###############################################################################
# Function to ask restore scope
###############################################################################
ask_restore_scope() {
    echo -e "${YELLOW}What would you like to restore?${NC}"
    echo ""
    echo -e "${CYAN}[1]${NC} Custom keybindings only"
    echo -e "${CYAN}[2]${NC} All keybindings (system + custom)"
    echo -e "${CYAN}[3]${NC} Dock configuration only"
    echo -e "${CYAN}[4]${NC} Everything (all keybindings + dock)"
    echo ""
    echo -e -n "${YELLOW}Your choice [1-4]: ${NC}"
    read -r RESTORE_CHOICE
    
    case $RESTORE_CHOICE in
        1)
            RESTORE_CUSTOM_ONLY=true
            RESTORE_ALL_KEYBINDINGS=false
            RESTORE_DOCK=false
            ;;
        2)
            RESTORE_CUSTOM_ONLY=false
            RESTORE_ALL_KEYBINDINGS=true
            RESTORE_DOCK=false
            ;;
        3)
            RESTORE_CUSTOM_ONLY=false
            RESTORE_ALL_KEYBINDINGS=false
            RESTORE_DOCK=true
            ;;
        4)
            RESTORE_CUSTOM_ONLY=false
            RESTORE_ALL_KEYBINDINGS=true
            RESTORE_DOCK=true
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
    echo ""
}

###############################################################################
# Function to restore custom keybindings
###############################################################################
restore_custom_keybindings() {
    echo -e "${YELLOW}[•] Restoring custom keybindings...${NC}"
    
    local custom_kb_file="${SELECTED_BACKUP}/custom-keybindings.dconf"
    
    if [ ! -f "$custom_kb_file" ]; then
        echo -e "${RED}  ✗ Custom keybindings backup not found${NC}"
        return 1
    fi
    
    # Clear existing custom keybindings first
    echo "  - Clearing existing custom keybindings..."
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[]"
    
    # Restore custom keybindings
    echo "  - Loading custom keybindings from backup..."
    dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "$custom_kb_file"
    
    # Verify restoration
    local restored_count=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | grep -o '/' | wc -l)
    
    echo -e "${GREEN}  ✓ Custom keybindings restored (${restored_count} custom keybindings)${NC}"
}

###############################################################################
# Function to restore all keybindings
###############################################################################
restore_all_keybindings() {
    echo -e "${YELLOW}[•] Restoring all keybindings...${NC}"
    
    local keybinding_schemas=(
        "org.gnome.desktop.wm.keybindings"
        "org.gnome.mutter.keybindings"
        "org.gnome.mutter.wayland.keybindings"
        "org.gnome.settings-daemon.plugins.media-keys"
        "org.gnome.shell.keybindings"
    )
    
    for schema in "${keybinding_schemas[@]}"; do
        local schema_file="${SELECTED_BACKUP}/${schema}.dconf"
        
        if [ -f "$schema_file" ]; then
            echo "  - Restoring ${schema}..."
            dconf load "/${schema//./\/}/" < "$schema_file"
        else
            echo "  - Skipping ${schema} (not found in backup)"
        fi
    done
    
    # Also restore custom keybindings
    restore_custom_keybindings
    
    echo -e "${GREEN}  ✓ All keybindings restored${NC}"
}

###############################################################################
# Function to restore dock configuration
###############################################################################
restore_dock() {
    echo -e "${YELLOW}[•] Restoring dock configuration...${NC}"
    
    # Restore favorite apps
    local fav_apps_file="${SELECTED_BACKUP}/favorite-apps.txt"
    if [ -f "$fav_apps_file" ]; then
        echo "  - Restoring favorite applications..."
        local favorites=$(cat "$fav_apps_file")
        gsettings set org.gnome.shell favorite-apps "$favorites"
    fi
    
    # Restore GNOME Shell settings
    local gnome_shell_file="${SELECTED_BACKUP}/org.gnome.shell.dconf"
    if [ -f "$gnome_shell_file" ]; then
        echo "  - Restoring GNOME Shell configuration..."
        dconf load /org/gnome/shell/ < "$gnome_shell_file"
    fi
    
    # Restore Dash-to-Dock if it exists
    local dash_to_dock_file="${SELECTED_BACKUP}/dash-to-dock.dconf"
    if [ -f "$dash_to_dock_file" ]; then
        if gsettings list-schemas | grep -q "org.gnome.shell.extensions.dash-to-dock"; then
            echo "  - Restoring Dash-to-Dock configuration..."
            dconf load /org/gnome/shell/extensions/dash-to-dock/ < "$dash_to_dock_file"
        else
            echo -e "  ${YELLOW}! Dash-to-Dock not installed, skipping${NC}"
        fi
    fi
    
    # Restore Dash-to-Panel if it exists
    local dash_to_panel_file="${SELECTED_BACKUP}/dash-to-panel.dconf"
    if [ -f "$dash_to_panel_file" ]; then
        if gsettings list-schemas | grep -q "org.gnome.shell.extensions.dash-to-panel"; then
            echo "  - Restoring Dash-to-Panel configuration..."
            dconf load /org/gnome/shell/extensions/dash-to-panel/ < "$dash_to_panel_file"
        else
            echo -e "  ${YELLOW}! Dash-to-Panel not installed, skipping${NC}"
        fi
    fi
    
    echo -e "${GREEN}  ✓ Dock configuration restored${NC}"
}

###############################################################################
# Function to restart GNOME Shell
###############################################################################
restart_gnome_shell() {
    echo ""
    echo -e "${YELLOW}Would you like to restart GNOME Shell to apply changes?${NC}"
    echo -e "${CYAN}Note: This will briefly freeze your screen${NC}"
    echo ""
    echo -e -n "${YELLOW}Restart GNOME Shell? [y/N]: ${NC}"
    read -r restart_choice
    
    if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
        if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
            echo -e "${YELLOW}Running on Wayland - you'll need to log out and back in for all changes to take effect${NC}"
            echo "Changes have been applied, but a logout/login is recommended."
        else
            echo "Restarting GNOME Shell..."
            killall -SIGQUIT gnome-shell 2>/dev/null || true
            echo -e "${GREEN}GNOME Shell restarted${NC}"
        fi
    else
        echo "Skipping GNOME Shell restart."
        echo -e "${YELLOW}Note: You may need to log out and back in for all changes to take effect${NC}"
    fi
}

###############################################################################
# Main execution
###############################################################################
main() {
    select_backup
    ask_restore_scope
    
    echo -e "${BLUE}Starting restore process...${NC}"
    echo ""
    
    # Restore based on user choice
    if [ "$RESTORE_ALL_KEYBINDINGS" = true ]; then
        restore_all_keybindings
    elif [ "$RESTORE_CUSTOM_ONLY" = true ]; then
        restore_custom_keybindings
    fi
    
    if [ "$RESTORE_DOCK" = true ]; then
        restore_dock
    fi
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Restore completed successfully!                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    restart_gnome_shell
    
    echo ""
    echo -e "${CYAN}Restore Summary:${NC}"
    if [ "$RESTORE_ALL_KEYBINDINGS" = true ]; then
        echo "  ✓ All keybindings restored"
    elif [ "$RESTORE_CUSTOM_ONLY" = true ]; then
        echo "  ✓ Custom keybindings restored"
    fi
    if [ "$RESTORE_DOCK" = true ]; then
        echo "  ✓ Dock configuration restored"
    fi
    echo ""
    echo -e "${YELLOW}Tip: If keybindings don't work immediately, try logging out and back in${NC}"
    echo ""
}

# Run main function
main
