#!/bin/bash

###############################################################################
# Ubuntu Keybindings and Dock Restore Script (IMPROVED)
# 
# This script restores:
# - GNOME keybindings (all or custom only)
# - Dock/Dash-to-Dock configuration
# - Favorite applications (dock icons)
#
# IMPROVEMENTS:
# - Merge or Replace option for custom keybindings
# - Automatic safety backup before restore
# - Better error handling
#
# Author: ecloaiza
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
echo -e "${BLUE}║  Ubuntu Keybindings & Dock Restore Script (v2)        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

###############################################################################
# Function to select backup
###############################################################################
select_backup() {
    echo -e "${YELLOW}Available backups:${NC}"
    echo ""
    
    if [ ! -d "${BACKUP_DIR}" ]; then
        echo -e "${RED}Error: No backup directory found at ${BACKUP_DIR}${NC}"
        exit 1
    fi
    
    local backups=($(ls -1dt "${BACKUP_DIR}"/backup_* 2>/dev/null || true))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}Error: No backups found${NC}"
        exit 1
    fi
    
    local i=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_date=$(echo "$backup_name" | sed 's/backup_//' | sed 's/_/ /')
        
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
    
    echo -e -n "${YELLOW}Select backup [1-${#backups[@]}] or 'latest': ${NC}"
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
    echo -e "${GREEN}Selected: $(basename "$SELECTED_BACKUP")${NC}"
    echo ""
}

###############################################################################
# Function to ask restore scope
###############################################################################
ask_restore_scope() {
    echo -e "${YELLOW}What to restore?${NC}"
    echo ""
    echo -e "${CYAN}[1]${NC} Custom keybindings only"
    echo -e "${CYAN}[2]${NC} All keybindings (system + custom)"
    echo -e "${CYAN}[3]${NC} Dock configuration only"
    echo -e "${CYAN}[4]${NC} Everything"
    echo ""
    echo -e -n "${YELLOW}Choice [1-4]: ${NC}"
    read -r RESTORE_CHOICE
    
    case $RESTORE_CHOICE in
        1) RESTORE_CUSTOM_ONLY=true; RESTORE_ALL_KEYBINDINGS=false; RESTORE_DOCK=false ;;
        2) RESTORE_CUSTOM_ONLY=false; RESTORE_ALL_KEYBINDINGS=true; RESTORE_DOCK=false ;;
        3) RESTORE_CUSTOM_ONLY=false; RESTORE_ALL_KEYBINDINGS=false; RESTORE_DOCK=true ;;
        4) RESTORE_CUSTOM_ONLY=false; RESTORE_ALL_KEYBINDINGS=true; RESTORE_DOCK=true ;;
        *) echo -e "${RED}Invalid${NC}"; exit 1 ;;
    esac
    echo ""
    
    if [ "$RESTORE_CUSTOM_ONLY" = true ] || [ "$RESTORE_ALL_KEYBINDINGS" = true ]; then
        echo -e "${YELLOW}How to restore custom keybindings?${NC}"
        echo ""
        echo -e "${CYAN}[1]${NC} Merge - Add to existing ${GREEN}(SAFE - recommended)${NC}"
        echo -e "${CYAN}[2]${NC} Replace - Delete all existing first ${RED}(DESTRUCTIVE)${NC}"
        echo ""
        echo -e -n "${YELLOW}Choice [1-2]: ${NC}"
        read -r MERGE_CHOICE
        
        case $MERGE_CHOICE in
            1) MERGE_KEYBINDINGS=true; echo -e "${GREEN}Will merge${NC}" ;;
            2) MERGE_KEYBINDINGS=false; echo -e "${YELLOW}Will replace${NC}" ;;
            *) MERGE_KEYBINDINGS=true; echo -e "${YELLOW}Defaulting to merge${NC}" ;;
        esac
        echo ""
    fi
}

###############################################################################
# Function to create safety backup
###############################################################################
create_safety_backup() {
    echo -e "${YELLOW}[•] Creating safety backup...${NC}"
    
    SAFETY_BACKUP_DIR="${BACKUP_DIR}/safety_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$SAFETY_BACKUP_DIR"
    
    dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "${SAFETY_BACKUP_DIR}/custom-keybindings.dconf" 2>/dev/null || true
    gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings > "${SAFETY_BACKUP_DIR}/custom-paths.txt" 2>/dev/null || true
    
    echo -e "${GREEN}  ✓ Safety backup: ${SAFETY_BACKUP_DIR}${NC}"
}

###############################################################################
# Function to restore custom keybindings
###############################################################################
restore_custom_keybindings() {
    echo -e "${YELLOW}[•] Restoring custom keybindings...${NC}"
    
    local custom_kb_file="${SELECTED_BACKUP}/custom-keybindings.dconf"
    
    if [ ! -f "$custom_kb_file" ]; then
        echo -e "${RED}  ✗ Backup file not found${NC}"
        return 1
    fi
    
    create_safety_backup
    
    if [ "$MERGE_KEYBINDINGS" = true ]; then
        echo "  - Mode: MERGE (preserving existing)"
        
        # Get current paths
        local current_paths=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)
        
        # Find highest number
        local max_num=0
        if [ "$current_paths" != "[]" ] && [ "$current_paths" != "@as []" ]; then
            max_num=$(echo "$current_paths" | grep -oP "custom[0-9]+" | sed 's/custom//' | sort -n | tail -1 || echo "0")
            max_num=$((max_num + 1))
        fi
        
        # Load backup to temp location first
        local temp_restore="/tmp/custom-kb-restore-$$"
        dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "$temp_restore" 2>/dev/null
        dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "$custom_kb_file"
        
        # Get what was just loaded
        local backup_paths=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        
        # Restore original
        if [ -f "$temp_restore" ]; then
            dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "$temp_restore"
            rm "$temp_restore"
        fi
        
        # Now merge them
        local base_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
        local new_paths=()
        
        # Extract each keybinding from backup and create with new number
        echo "$backup_paths" | tr -d "[]'" | tr ',' '\n' | while read -r path; do
            path=$(echo "$path" | xargs)
            if [ -n "$path" ]; then
                # Get the keybinding details from backup (temporarily load it)
                dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "$custom_kb_file"
                
                local name=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" name 2>/dev/null || echo "")
                local command=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" command 2>/dev/null || echo "")
                local binding=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" binding 2>/dev/null || echo "")
                
                # Restore current state
                if [ -f "${SAFETY_BACKUP_DIR}/custom-keybindings.dconf" ]; then
                    dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "${SAFETY_BACKUP_DIR}/custom-keybindings.dconf"
                fi
                
                if [ -n "$name" ] && [ "$name" != "''" ]; then
                    local new_path="${base_path}/custom${max_num}/"
                    
                    echo "    + $(echo $name | tr -d "'")"
                    
                    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${new_path}" name "$name"
                    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${new_path}" command "$command"
                    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${new_path}" binding "$binding"
                    
                    new_paths+=("'${new_path}'")
                    max_num=$((max_num + 1))
                fi
            fi
        done
        
        # Update paths list
        if [ ${#new_paths[@]} -gt 0 ]; then
            local all_paths=()
            
            if [ "$current_paths" != "[]" ] && [ "$current_paths" != "@as []" ]; then
                while IFS= read -r p; do
                    [ -n "$p" ] && all_paths+=("$p")
                done < <(echo "$current_paths" | tr -d '[]' | tr ',' '\n' | xargs -n1 echo)
            fi
            
            all_paths+=("${new_paths[@]}")
            
            local combined=$(printf "%s," "${all_paths[@]}")
            combined="[${combined%,}]"
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$combined"
        fi
        
    else
        echo "  - Mode: REPLACE (deleting all existing)"
        
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[]"
        dconf reset -f /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/
        
        dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "$custom_kb_file"
    fi
    
    local final_count=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | grep -o '/' | wc -l)
    echo -e "${GREEN}  ✓ Done (${final_count} total keybindings)${NC}"
}

###############################################################################
# Function to restore all keybindings
###############################################################################
restore_all_keybindings() {
    echo -e "${YELLOW}[•] Restoring all keybindings...${NC}"
    
    local schemas=(
        "org.gnome.desktop.wm.keybindings"
        "org.gnome.mutter.keybindings"
        "org.gnome.mutter.wayland.keybindings"
        "org.gnome.settings-daemon.plugins.media-keys"
        "org.gnome.shell.keybindings"
    )
    
    for schema in "${schemas[@]}"; do
        local file="${SELECTED_BACKUP}/${schema}.dconf"
        if [ -f "$file" ]; then
            echo "  - ${schema}"
            dconf load "/${schema//./\/}/" < "$file"
        fi
    done
    
    restore_custom_keybindings
    echo -e "${GREEN}  ✓ All keybindings restored${NC}"
}

###############################################################################
# Function to restore dock
###############################################################################
restore_dock() {
    echo -e "${YELLOW}[•] Restoring dock...${NC}"
    
    if [ -f "${SELECTED_BACKUP}/favorite-apps.txt" ]; then
        echo "  - Favorite apps"
        gsettings set org.gnome.shell favorite-apps "$(cat "${SELECTED_BACKUP}/favorite-apps.txt")"
    fi
    
    if [ -f "${SELECTED_BACKUP}/org.gnome.shell.dconf" ]; then
        echo "  - GNOME Shell settings"
        dconf load /org/gnome/shell/ < "${SELECTED_BACKUP}/org.gnome.shell.dconf"
    fi
    
    if [ -f "${SELECTED_BACKUP}/dash-to-dock.dconf" ]; then
        if gsettings list-schemas | grep -q "org.gnome.shell.extensions.dash-to-dock"; then
            echo "  - Dash-to-Dock"
            dconf load /org/gnome/shell/extensions/dash-to-dock/ < "${SELECTED_BACKUP}/dash-to-dock.dconf"
        fi
    fi
    
    echo -e "${GREEN}  ✓ Dock restored${NC}"
}

###############################################################################
# Main
###############################################################################
main() {
    select_backup
    ask_restore_scope
    
    echo -e "${BLUE}Restoring...${NC}"
    echo ""
    
    if [ "$RESTORE_ALL_KEYBINDINGS" = true ]; then
        restore_all_keybindings
    elif [ "$RESTORE_CUSTOM_ONLY" = true ]; then
        restore_custom_keybindings
    fi
    
    [ "$RESTORE_DOCK" = true ] && restore_dock
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Restore completed!                                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -n "$SAFETY_BACKUP_DIR" ]; then
        echo -e "${CYAN}💾 Safety backup: ${SAFETY_BACKUP_DIR}${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}Restart GNOME Shell? [y/N]: ${NC}"
    read -r restart
    
    if [[ "$restart" =~ ^[Yy]$ ]]; then
        if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
            echo -e "${YELLOW}Wayland detected - please log out/in${NC}"
        else
            killall -SIGQUIT gnome-shell 2>/dev/null || true
            echo -e "${GREEN}GNOME Shell restarted${NC}"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}Tip: Log out/in if keybindings don't work immediately${NC}"
    echo ""
}

main