#!/bin/bash

###############################################################################
# Ubuntu Keybindings and Dock Restore Script v3 - SIMPLIFIED
# 
# This version uses a straightforward approach that actually works:
# - Direct dconf load for reliability
# - Proper path handling
# - Better merge logic
#
# Author: ecloaiza
###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Ubuntu Keybindings & Dock Restore Script v3          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

###############################################################################
# Select backup
###############################################################################
select_backup() {
    echo -e "${YELLOW}Available backups:${NC}"
    echo ""
    
    if [ ! -d "${BACKUP_DIR}" ]; then
        echo -e "${RED}No backups found. Run ./backup_keybindings.sh first${NC}"
        exit 1
    fi
    
    local backups=($(ls -1dt "${BACKUP_DIR}"/backup_* 2>/dev/null || true))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}No backups found. Run ./backup_keybindings.sh first${NC}"
        exit 1
    fi
    
    local i=1
    for backup in "${backups[@]}"; do
        local name=$(basename "$backup")
        local date=$(echo "$name" | sed 's/backup_//' | sed 's/_/ /')
        echo -e "${CYAN}[$i]${NC} ${date}"
        
        if [ -f "$backup/metadata.txt" ]; then
            grep "Hostname:" "$backup/metadata.txt" | sed 's/^/    /'
        fi
        echo ""
        ((i++))
    done
    
    echo -e -n "${YELLOW}Select [1-${#backups[@]}] or 'l' for latest: ${NC}"
    read -r selection
    
    if [ "$selection" = "l" ] || [ "$selection" = "latest" ]; then
        if [ -L "${BACKUP_DIR}/latest" ]; then
            SELECTED_BACKUP=$(readlink -f "${BACKUP_DIR}/latest")
        else
            SELECTED_BACKUP="${backups[0]}"
        fi
    else
        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backups[@]} ]; then
            echo -e "${RED}Invalid selection${NC}"
            exit 1
        fi
        SELECTED_BACKUP="${backups[$((selection-1))]}"
    fi
    
    echo ""
    echo -e "${GREEN}Using: $(basename "$SELECTED_BACKUP")${NC}"
    echo ""
}

###############################################################################
# Choose what to restore
###############################################################################
choose_restore_options() {
    echo -e "${YELLOW}What to restore?${NC}"
    echo ""
    echo -e "${CYAN}[1]${NC} Custom keybindings only"
    echo -e "${CYAN}[2]${NC} All keybindings"
    echo -e "${CYAN}[3]${NC} Dock only"
    echo -e "${CYAN}[4]${NC} Everything"
    echo ""
    echo -e -n "${YELLOW}Choice [1-4]: ${NC}"
    read -r choice
    
    case $choice in
        1) RESTORE_CUSTOM=true; RESTORE_SYSTEM=false; RESTORE_DOCK=false ;;
        2) RESTORE_CUSTOM=true; RESTORE_SYSTEM=true; RESTORE_DOCK=false ;;
        3) RESTORE_CUSTOM=false; RESTORE_SYSTEM=false; RESTORE_DOCK=true ;;
        4) RESTORE_CUSTOM=true; RESTORE_SYSTEM=true; RESTORE_DOCK=true ;;
        *) echo -e "${RED}Invalid${NC}"; exit 1 ;;
    esac
    echo ""
    
    if [ "$RESTORE_CUSTOM" = true ]; then
        echo -e "${YELLOW}Custom keybindings restore mode:${NC}"
        echo ""
        echo -e "${CYAN}[1]${NC} Merge - Add to existing ${GREEN}(SAFE)${NC}"
        echo -e "${CYAN}[2]${NC} Replace - Delete existing first ${RED}(CAUTION)${NC}"
        echo ""
        echo -e -n "${YELLOW}Choice [1-2]: ${NC}"
        read -r merge_choice
        
        if [ "$merge_choice" = "2" ]; then
            MERGE_MODE=false
            echo -e "${YELLOW}Will replace existing${NC}"
        else
            MERGE_MODE=true
            echo -e "${GREEN}Will merge with existing${NC}"
        fi
        echo ""
    fi
}

###############################################################################
# Create safety backup
###############################################################################
create_safety_backup() {
    SAFETY_DIR="${BACKUP_DIR}/safety_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$SAFETY_DIR"
    
    echo -e "${CYAN}Creating safety backup...${NC}"
    dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "${SAFETY_DIR}/custom-keybindings.dconf" 2>/dev/null || true
    gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings > "${SAFETY_DIR}/paths.txt" 2>/dev/null || true
    
    echo -e "${GREEN}Safety backup: ${SAFETY_DIR}${NC}"
    echo ""
}

###############################################################################
# Restore custom keybindings - WORKING VERSION
###############################################################################
restore_custom_keybindings() {
    echo -e "${YELLOW}[•] Restoring custom keybindings...${NC}"
    
    local backup_file="${SELECTED_BACKUP}/custom-keybindings.dconf"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Backup file not found: $backup_file${NC}"
        return 1
    fi
    
    # Show what's in the backup
    echo -e "${CYAN}Found in backup:${NC}"
    grep "^\[" "$backup_file" | wc -l | xargs -I {} echo "  {} keybindings"
    echo ""
    
    create_safety_backup
    
    if [ "$MERGE_MODE" = false ]; then
        # REPLACE MODE - simple and clean
        echo "  Mode: REPLACE"
        echo "  Clearing existing keybindings..."
        
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[]"
        dconf reset -f /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/
        
        echo "  Loading from backup..."
        dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "$backup_file"
        
        # Get the paths from backup file and set them
        local backup_paths=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        echo "  Setting keybinding paths..."
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$backup_paths"
        
    else
        # MERGE MODE - preserve existing
        echo "  Mode: MERGE"
        
        # Get current keybindings count
        local current_paths=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        local current_max=0
        
        if [ "$current_paths" != "[]" ] && [ "$current_paths" != "@as []" ]; then
            current_max=$(echo "$current_paths" | grep -oP "custom\K[0-9]+" | sort -n | tail -1 || echo "0")
            current_max=$((current_max + 1))
            echo "  Current keybindings: $(echo "$current_paths" | grep -o "custom" | wc -l)"
            echo "  Next available slot: custom${current_max}"
        else
            echo "  No existing keybindings found"
        fi
        echo ""
        
        # Parse backup file and extract keybindings
        local base_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
        local new_paths=()
        local kb_count=0
        
        # First, temporarily load backup to read values
        local temp_area="/tmp/kb-restore-$$"
        dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "$temp_area" 2>/dev/null || echo "" > "$temp_area"
        dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "$backup_file"
        
        # Get all custom keybinding paths from backup
        local backup_kb_list=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        
        echo "  Adding from backup:"
        
        # Process each keybinding from backup
        echo "$backup_kb_list" | tr -d "[]'" | tr ',' '\n' | while IFS= read -r old_path; do
            old_path=$(echo "$old_path" | xargs)
            
            if [ -n "$old_path" ]; then
                # Read values from backup
                local name=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${old_path}" name 2>/dev/null)
                local command=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${old_path}" command 2>/dev/null)
                local binding=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${old_path}" binding 2>/dev/null)
                
                if [ -n "$name" ] && [ "$name" != "''" ]; then
                    echo "    $(echo $name | tr -d "'")"
                    
                    # Store for later
                    echo "$name|$command|$binding|$current_max" >> "${SAFETY_DIR}/to_restore.txt"
                    
                    current_max=$((current_max + 1))
                    kb_count=$((kb_count + 1))
                fi
            fi
        done
        
        # Restore original state
        dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < "$temp_area"
        rm -f "$temp_area"
        
        # Now actually add the keybindings
        if [ -f "${SAFETY_DIR}/to_restore.txt" ]; then
            while IFS='|' read -r name command binding slot; do
                local new_path="${base_path}/custom${slot}/"
                
                gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${new_path}" name "$name"
                gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${new_path}" command "$command"
                gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${new_path}" binding "$binding"
                
                new_paths+=("'${new_path}'")
            done < "${SAFETY_DIR}/to_restore.txt"
            
            # Update the paths list
            local all_paths=()
            
            if [ "$current_paths" != "[]" ] && [ "$current_paths" != "@as []" ]; then
                while IFS= read -r p; do
                    p=$(echo "$p" | xargs)
                    [ -n "$p" ] && all_paths+=("$p")
                done < <(echo "$current_paths" | tr -d '[]' | tr ',' '\n')
            fi
            
            all_paths+=("${new_paths[@]}")
            
            local final_list=$(printf "%s," "${all_paths[@]}")
            final_list="[${final_list%,}]"
            
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$final_list"
            
            echo ""
            echo "  Added ${kb_count} keybindings"
        fi
    fi
    
    # Verify
    local final_count=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | grep -o "custom" | wc -l || echo "0")
    echo -e "${GREEN}✓ Done - Total keybindings: ${final_count}${NC}"
}

###############################################################################
# Restore system keybindings
###############################################################################
restore_system_keybindings() {
    echo -e "${YELLOW}[•] Restoring system keybindings...${NC}"
    
    local schemas=(
        "org.gnome.desktop.wm.keybindings"
        "org.gnome.mutter.keybindings"
        "org.gnome.settings-daemon.plugins.media-keys"
        "org.gnome.shell.keybindings"
    )
    
    for schema in "${schemas[@]}"; do
        local file="${SELECTED_BACKUP}/${schema}.dconf"
        if [ -f "$file" ]; then
            echo "  - $schema"
            dconf load "/${schema//./\/}/" < "$file"
        fi
    done
    
    echo -e "${GREEN}✓ System keybindings restored${NC}"
}

###############################################################################
# Restore dock
###############################################################################
restore_dock() {
    echo -e "${YELLOW}[•] Restoring dock...${NC}"
    
    if [ -f "${SELECTED_BACKUP}/favorite-apps.txt" ]; then
        local apps=$(cat "${SELECTED_BACKUP}/favorite-apps.txt")
        gsettings set org.gnome.shell favorite-apps "$apps"
        echo "  - Favorite apps"
    fi
    
    if [ -f "${SELECTED_BACKUP}/org.gnome.shell.dconf" ]; then
        dconf load /org/gnome/shell/ < "${SELECTED_BACKUP}/org.gnome.shell.dconf"
        echo "  - Shell config"
    fi
    
    if [ -f "${SELECTED_BACKUP}/dash-to-dock.dconf" ]; then
        if gsettings list-schemas | grep -q "dash-to-dock"; then
            dconf load /org/gnome/shell/extensions/dash-to-dock/ < "${SELECTED_BACKUP}/dash-to-dock.dconf"
            echo "  - Dash-to-Dock"
        fi
    fi
    
    echo -e "${GREEN}✓ Dock restored${NC}"
}

###############################################################################
# Main
###############################################################################
main() {
    select_backup
    choose_restore_options
    
    echo -e "${BLUE}Starting restore...${NC}"
    echo ""
    
    [ "$RESTORE_SYSTEM" = true ] && restore_system_keybindings
    [ "$RESTORE_CUSTOM" = true ] && restore_custom_keybindings
    [ "$RESTORE_DOCK" = true ] && restore_dock
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Restore Complete!                                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -n "$SAFETY_DIR" ]; then
        echo -e "${CYAN}Safety backup: ${SAFETY_DIR}${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}Test your keybindings now. If they don't work:${NC}"
    echo "  1. Log out and log back in"
    echo "  2. Check that required apps are installed"
    echo ""
    
    echo -e -n "${YELLOW}Restart GNOME Shell now? [y/N]: ${NC}"
    read -r restart
    
    if [[ "$restart" =~ ^[Yy]$ ]]; then
        if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
            echo -e "${YELLOW}On Wayland - please log out/in manually${NC}"
        else
            killall -SIGQUIT gnome-shell 2>/dev/null || true
            echo -e "${GREEN}GNOME Shell restarted${NC}"
        fi
    fi
}

main