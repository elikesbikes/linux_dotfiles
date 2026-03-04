#!/bin/bash

###############################################################################
# Debug Script - Check Keybindings Status
# 
# Use this to diagnose keybinding problems
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Keybindings Debug Information                        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}=== Current Custom Keybindings ===${NC}"
echo ""

# Get the list of custom keybindings
custom_paths=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)

echo "Paths list:"
echo "$custom_paths"
echo ""

if [ "$custom_paths" = "[]" ] || [ "$custom_paths" = "@as []" ]; then
    echo -e "${RED}No custom keybindings found${NC}"
    echo ""
else
    count=$(echo "$custom_paths" | grep -o "custom" | wc -l)
    echo -e "${GREEN}Found $count custom keybindings${NC}"
    echo ""
    
    echo -e "${YELLOW}Details:${NC}"
    echo ""
    
    # Parse and show each keybinding
    echo "$custom_paths" | tr -d "[]'" | tr ',' '\n' | while IFS= read -r path; do
        path=$(echo "$path" | xargs)
        
        if [ -n "$path" ]; then
            name=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" name 2>/dev/null || echo "ERROR")
            command=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" command 2>/dev/null || echo "ERROR")
            binding=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"${path}" binding 2>/dev/null || echo "ERROR")
            
            echo -e "${CYAN}Path:${NC} $path"
            echo -e "${CYAN}Name:${NC} $name"
            echo -e "${CYAN}Command:${NC} $command"
            echo -e "${CYAN}Binding:${NC} $binding"
            echo ""
        fi
    done
fi

echo -e "${YELLOW}=== Latest Backup Content ===${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LATEST_BACKUP="${SCRIPT_DIR}/backups/latest"

if [ -L "$LATEST_BACKUP" ]; then
    echo "Latest backup: $(readlink -f "$LATEST_BACKUP")"
    echo ""
    
    backup_file="${LATEST_BACKUP}/custom-keybindings.dconf"
    
    if [ -f "$backup_file" ]; then
        echo "Custom keybindings in backup:"
        grep "^\[" "$backup_file" | wc -l | xargs -I {} echo "  {} keybindings found"
        echo ""
        
        echo "Paths in backup:"
        grep "^\[" "$backup_file" | head -10
        echo ""
        
        if [ -f "${LATEST_BACKUP}/keybindings_readable.txt" ]; then
            echo "Readable format available:"
            echo "  cat ${LATEST_BACKUP}/keybindings_readable.txt"
        fi
    else
        echo -e "${RED}No backup file found${NC}"
    fi
else
    echo -e "${RED}No latest backup symlink found${NC}"
    echo "Run ./backup_keybindings.sh first"
fi

echo ""
echo -e "${YELLOW}=== System Information ===${NC}"
echo ""
echo "Desktop: $XDG_CURRENT_DESKTOP"
echo "Session: $XDG_SESSION_TYPE"
echo "Shell: $(gnome-shell --version 2>/dev/null || echo "Not found")"
echo ""

echo -e "${YELLOW}=== Backup Directories ===${NC}"
echo ""
ls -lh "${SCRIPT_DIR}/backups/" 2>/dev/null | tail -5 || echo "No backups found"
echo ""

echo -e "${YELLOW}=== Quick Test Commands ===${NC}"
echo ""
echo "View current keybindings:"
echo "  gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings"
echo ""
echo "View backup content:"
echo "  cat ${SCRIPT_DIR}/backups/latest/custom-keybindings.dconf"
echo ""
echo "Manually restore (CAUTION - replaces all):"
echo "  dconf load /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ < ${SCRIPT_DIR}/backups/latest/custom-keybindings.dconf"
echo ""