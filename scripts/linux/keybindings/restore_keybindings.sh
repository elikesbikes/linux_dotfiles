#!/bin/bash

###############################################################################
# Ubuntu Keybindings Restore Script v5 - ACTUALLY WORKING NOW
# 
# Fixed: Properly handles quoted values from dconf format
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Ubuntu Keybindings Restore Script v5                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

###############################################################################
# Select backup
###############################################################################
select_backup() {
    echo -e "${YELLOW}Available backups:${NC}"
    echo ""
    
    if [ ! -d "${BACKUP_DIR}" ]; then
        echo -e "${RED}No backups found${NC}"
        exit 1
    fi
    
    local backups=($(ls -1dt "${BACKUP_DIR}"/backup_* 2>/dev/null || true))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}No backups found${NC}"
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
            echo -e "${RED}Invalid${NC}"
            exit 1
        fi
        SELECTED_BACKUP="${backups[$((selection-1))]}"
    fi
    
    echo ""
    echo -e "${GREEN}Using: $(basename "$SELECTED_BACKUP")${NC}"
    echo ""
}

###############################################################################
# Choose options
###############################################################################
choose_options() {
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
        1) DO_CUSTOM=true; DO_SYSTEM=false; DO_DOCK=false ;;
        2) DO_CUSTOM=true; DO_SYSTEM=true; DO_DOCK=false ;;
        3) DO_CUSTOM=false; DO_SYSTEM=false; DO_DOCK=true ;;
        4) DO_CUSTOM=true; DO_SYSTEM=true; DO_DOCK=true ;;
        *) echo -e "${RED}Invalid${NC}"; exit 1 ;;
    esac
    echo ""
    
    if [ "$DO_CUSTOM" = true ]; then
        echo -e "${YELLOW}Restore mode:${NC}"
        echo ""
        echo -e "${CYAN}[1]${NC} Merge - Add to existing ${GREEN}(SAFE)${NC}"
        echo -e "${CYAN}[2]${NC} Replace - Delete all first ${RED}(CAUTION)${NC}"
        echo ""
        echo -e -n "${YELLOW}Choice [1-2]: ${NC}"
        read -r mode
        
        MERGE_MODE=true
        [ "$mode" = "2" ] && MERGE_MODE=false
        echo ""
    fi
}

###############################################################################
# Safety backup
###############################################################################
safety_backup() {
    SAFETY_DIR="${BACKUP_DIR}/safety_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$SAFETY_DIR"
    
    echo -e "${CYAN}Creating safety backup...${NC}"
    dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "${SAFETY_DIR}/custom.dconf" 2>/dev/null || true
    gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings > "${SAFETY_DIR}/paths.txt" 2>/dev/null || true
    echo -e "${GREEN}Safety: ${SAFETY_DIR}${NC}"
    echo ""
}

###############################################################################
# Parse dconf file - FIXED to handle quoted values correctly
###############################################################################
parse_dconf_file() {
    local file="$1"
    local -n result_array=$2
    
    local current_section=""
    local name="" command="" binding=""
    
    while IFS= read -r line; do
        # Section header like [custom0]
        if [[ "$line" =~ ^\[custom([0-9]+)\]$ ]]; then
            # Save previous entry if complete
            if [ -n "$current_section" ] && [ -n "$name" ] && [ -n "$command" ] && [ -n "$binding" ]; then
                result_array+=("$name|$command|$binding")
            fi
            
            # Start new entry
            current_section="${BASH_REMATCH[1]}"
            name=""
            command=""
            binding=""
            
        # Key-value pairs - values are already quoted in dconf format
        elif [[ "$line" =~ ^name=(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^command=(.+)$ ]]; then
            command="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^binding=(.+)$ ]]; then
            binding="${BASH_REMATCH[1]}"
        fi
    done < "$file"
    
    # Don't forget the last entry
    if [ -n "$current_section" ] && [ -n "$name" ] && [ -n "$command" ] && [ -n "$binding" ]; then
        result_array+=("$name|$command|$binding")
    fi
}

###############################################################################
# Restore custom keybindings - FIXED VERSION
###############################################################################
restore_custom() {
    echo -e "${YELLOW}[•] Restoring custom keybindings...${NC}"
    
    local backup_file="${SELECTED_BACKUP}/custom-keybindings.dconf"
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Backup file not found${NC}"
        return 1
    fi
    
    # Parse backup file
    local keybindings=()
    parse_dconf_file "$backup_file" keybindings
    
    if [ ${#keybindings[@]} -eq 0 ]; then
        echo -e "${YELLOW}No keybindings found in backup${NC}"
        return 0
    fi
    
    echo "Found ${#keybindings[@]} keybindings in backup"
    echo ""
    
    safety_backup
    
    local base_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
    
    if [ "$MERGE_MODE" = false ]; then
        # REPLACE MODE
        echo "Mode: REPLACE (clearing existing)"
        echo ""
        
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[]"
        dconf reset -f /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/
        
        local paths=()
        local index=0
        
        echo "Restoring:"
        for kb in "${keybindings[@]}"; do
            IFS='|' read -r name command binding <<< "$kb"
            
            # Values already have quotes from dconf file, use them as-is
            echo "  [$index] $(echo "$name" | sed "s/'//g")"
            
            local path="${base_path}/custom${index}/"
            
            # Use the quoted values directly - no extra quotes needed
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" name "$name"
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" command "$command"
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" binding "$binding"
            
            paths+=("'${path}'")
            index=$((index + 1))
        done
        
        # Set the paths list
        local paths_str=$(printf "%s," "${paths[@]}")
        paths_str="[${paths_str%,}]"
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$paths_str"
        
    else
        # MERGE MODE
        echo "Mode: MERGE (preserving existing)"
        echo ""
        
        # Get current keybindings
        local current_paths=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
        local start_index=0
        
        if [ "$current_paths" != "[]" ] && [ "$current_paths" != "@as []" ]; then
            start_index=$(echo "$current_paths" | grep -oP "custom\K[0-9]+" | sort -n | tail -1 || echo "0")
            start_index=$((start_index + 1))
            
            local existing_count=$(echo "$current_paths" | grep -o "custom" | wc -l)
            echo "Existing keybindings: $existing_count"
            echo "Will add new ones starting at custom${start_index}"
        else
            echo "No existing keybindings found"
        fi
        echo ""
        
        local new_paths=()
        local index=$start_index
        
        echo "Adding from backup:"
        for kb in "${keybindings[@]}"; do
            IFS='|' read -r name command binding <<< "$kb"
            
            # Display without quotes
            echo "  [$index] $(echo "$name" | sed "s/'//g")"
            
            local path="${base_path}/custom${index}/"
            
            # Use quoted values as-is from dconf file
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" name "$name"
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" command "$command"
            gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" binding "$binding"
            
            new_paths+=("'${path}'")
            index=$((index + 1))
        done
        
        # Merge with existing paths
        local all_paths=()
        
        if [ "$current_paths" != "[]" ] && [ "$current_paths" != "@as []" ]; then
            while IFS= read -r p; do
                p=$(echo "$p" | xargs)
                [ -n "$p" ] && all_paths+=("$p")
            done < <(echo "$current_paths" | tr -d '[]' | tr ',' '\n')
        fi
        
        all_paths+=("${new_paths[@]}")
        
        local final_str=$(printf "%s," "${all_paths[@]}")
        final_str="[${final_str%,}]"
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$final_str"
    fi
    
    echo ""
    local final_count=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | grep -o "custom" | wc -l || echo "0")
    echo -e "${GREEN}✓ Done - Total keybindings now: ${final_count}${NC}"
    
    # Show what was actually set for verification
    echo ""
    echo -e "${CYAN}Verification:${NC}"
    local verify_paths=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    echo "$verify_paths" | tr -d '[]' | tr ',' '\n' | while read -r vp; do
        vp=$(echo "$vp" | xargs | tr -d "'")
        if [ -n "$vp" ]; then
            local vname=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${vp}" name 2>/dev/null | sed "s/'//g")
            [ -n "$vname" ] && echo "  ✓ $vname"
        fi
    done
}

###############################################################################
# Restore system keybindings
###############################################################################
restore_system() {
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
        gsettings set org.gnome.shell favorite-apps "$(cat "${SELECTED_BACKUP}/favorite-apps.txt")"
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
    choose_options
    
    echo -e "${BLUE}Starting restore...${NC}"
    echo ""
    
    [ "$DO_SYSTEM" = true ] && restore_system
    [ "$DO_CUSTOM" = true ] && restore_custom
    [ "$DO_DOCK" = true ] && restore_dock
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Restore Complete!                                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    [ -n "$SAFETY_DIR" ] && echo -e "${CYAN}Safety: ${SAFETY_DIR}${NC}" && echo ""
    
    echo -e "${YELLOW}Test your keybindings now!${NC}"
    echo ""
    echo "If they don't work immediately:"
    echo "  1. Try logging out and back in"
    echo "  2. Check that apps are installed (ulauncher, flameshot, etc.)"
    echo ""
    
    echo -e -n "${YELLOW}Restart GNOME Shell? [y/N]: ${NC}"
    read -r restart
    
    if [[ "$restart" =~ ^[Yy]$ ]]; then
        if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
            echo -e "${YELLOW}Wayland: Please log out/in for changes to take full effect${NC}"
        else
            killall -SIGQUIT gnome-shell 2>/dev/null || true
            echo -e "${GREEN}GNOME Shell restarted${NC}"
        fi
    fi
}

main