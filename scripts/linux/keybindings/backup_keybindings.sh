#!/bin/bash

###############################################################################
# Ubuntu Keybindings and Dock Backup Script
# 
# This script backs up:
# - All GNOME keybindings (system and custom)
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
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_SUBDIR="${BACKUP_DIR}/backup_${TIMESTAMP}"

# Create backup directory
mkdir -p "${BACKUP_SUBDIR}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Ubuntu Keybindings & Dock Backup Script              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Backup location: ${BACKUP_SUBDIR}${NC}"
echo ""

###############################################################################
# Function to backup keybindings
###############################################################################
backup_keybindings() {
    echo -e "${YELLOW}[1/4] Backing up keybindings...${NC}"
    
    # Backup all keybinding schemas
    local keybinding_schemas=(
        "org.gnome.desktop.wm.keybindings"
        "org.gnome.mutter.keybindings"
        "org.gnome.mutter.wayland.keybindings"
        "org.gnome.settings-daemon.plugins.media-keys"
        "org.gnome.shell.keybindings"
    )
    
    for schema in "${keybinding_schemas[@]}"; do
        if gsettings list-schemas | grep -q "^${schema}$"; then
            echo "  - Backing up ${schema}..."
            dconf dump "/${schema//./\/}/" > "${BACKUP_SUBDIR}/${schema}.dconf"
        fi
    done
    
    # Backup custom keybindings
    echo "  - Backing up custom keybindings..."
    dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "${BACKUP_SUBDIR}/custom-keybindings.dconf"
    
    # Export all keybindings to a human-readable format
    {
        echo "# Ubuntu Keybindings Backup"
        echo "# Generated: $(date)"
        echo "# Hostname: $(hostname)"
        echo ""
        echo "## Custom Keybindings"
        echo ""
        
        # Get custom keybindings paths
        custom_paths=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "[]")
        
        if [ "$custom_paths" != "[]" ] && [ "$custom_paths" != "@as []" ]; then
            # Parse custom keybindings
            echo "$custom_paths" | tr -d "[]'" | tr ',' '\n' | while read -r path; do
                if [ -n "$path" ]; then
                    path=$(echo "$path" | xargs)  # trim whitespace
                    name=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$path" name 2>/dev/null || echo "")
                    command=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$path" command 2>/dev/null || echo "")
                    binding=$(gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$path" binding 2>/dev/null || echo "")
                    
                    if [ -n "$name" ]; then
                        echo "### $name"
                        echo "Path: $path"
                        echo "Command: $command"
                        echo "Binding: $binding"
                        echo ""
                    fi
                fi
            done
        else
            echo "No custom keybindings found."
            echo ""
        fi
        
        echo "## System Keybindings"
        echo ""
        
        for schema in "${keybinding_schemas[@]}"; do
            if gsettings list-schemas | grep -q "^${schema}$"; then
                echo "### ${schema}"
                gsettings list-keys "$schema" 2>/dev/null | while read -r key; do
                    value=$(gsettings get "$schema" "$key" 2>/dev/null || echo "")
                    if [ -n "$value" ] && [ "$value" != "@as []" ] && [ "$value" != "[]" ]; then
                        echo "$key = $value"
                    fi
                done
                echo ""
            fi
        done
        
    } > "${BACKUP_SUBDIR}/keybindings_readable.txt"
    
    echo -e "${GREEN}  ✓ Keybindings backed up${NC}"
}

###############################################################################
# Function to backup dock configuration
###############################################################################
backup_dock() {
    echo -e "${YELLOW}[2/4] Backing up dock configuration...${NC}"
    
    # Backup GNOME Shell favorite apps (dock icons)
    if gsettings list-schemas | grep -q "org.gnome.shell"; then
        echo "  - Backing up favorite applications..."
        favorites=$(gsettings get org.gnome.shell favorite-apps)
        echo "$favorites" > "${BACKUP_SUBDIR}/favorite-apps.txt"
        
        # Also save as dconf
        dconf dump /org/gnome/shell/ > "${BACKUP_SUBDIR}/org.gnome.shell.dconf"
    fi
    
    # Backup Dash-to-Dock settings if installed
    if gsettings list-schemas | grep -q "org.gnome.shell.extensions.dash-to-dock"; then
        echo "  - Backing up Dash-to-Dock configuration..."
        dconf dump /org/gnome/shell/extensions/dash-to-dock/ > "${BACKUP_SUBDIR}/dash-to-dock.dconf"
    fi
    
    # Backup Ubuntu Dock settings if available
    if gsettings list-schemas | grep -q "org.gnome.shell.extensions.dash-to-panel"; then
        echo "  - Backing up Dash-to-Panel configuration..."
        dconf dump /org/gnome/shell/extensions/dash-to-panel/ > "${BACKUP_SUBDIR}/dash-to-panel.dconf"
    fi
    
    # Create human-readable dock config
    {
        echo "# Dock Configuration Backup"
        echo "# Generated: $(date)"
        echo ""
        echo "## Favorite Applications (Dock Icons)"
        echo "$favorites" | tr -d "[]'" | tr ',' '\n' | while read -r app; do
            if [ -n "$app" ]; then
                echo "  - $(echo "$app" | xargs)"
            fi
        done
    } > "${BACKUP_SUBDIR}/dock_readable.txt"
    
    echo -e "${GREEN}  ✓ Dock configuration backed up${NC}"
}

###############################################################################
# Function to create backup metadata
###############################################################################
create_metadata() {
    echo -e "${YELLOW}[3/4] Creating backup metadata...${NC}"
    
    {
        echo "# Backup Metadata"
        echo "Timestamp: $TIMESTAMP"
        echo "Date: $(date)"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "Ubuntu Version: $(lsb_release -d | cut -f2)"
        echo "Desktop Environment: $XDG_CURRENT_DESKTOP"
        echo "Session Type: $XDG_SESSION_TYPE"
        echo ""
        echo "# Installed Extensions"
        gnome-extensions list 2>/dev/null || echo "Could not list extensions"
    } > "${BACKUP_SUBDIR}/metadata.txt"
    
    echo -e "${GREEN}  ✓ Metadata created${NC}"
}

###############################################################################
# Function to create latest symlink
###############################################################################
create_latest_link() {
    echo -e "${YELLOW}[4/4] Creating 'latest' symlink...${NC}"
    
    # Remove old latest link if it exists
    rm -f "${BACKUP_DIR}/latest"
    
    # Create new latest link
    ln -s "${BACKUP_SUBDIR}" "${BACKUP_DIR}/latest"
    
    echo -e "${GREEN}  ✓ Latest symlink created${NC}"
}

###############################################################################
# Main execution
###############################################################################
main() {
    backup_keybindings
    backup_dock
    create_metadata
    create_latest_link
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Backup completed successfully!                       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Backup saved to: ${BLUE}${BACKUP_SUBDIR}${NC}"
    echo -e "Quick access:    ${BLUE}${BACKUP_DIR}/latest${NC}"
    echo ""
    echo "Files created:"
    ls -lh "${BACKUP_SUBDIR}" | tail -n +2 | awk '{print "  - " $9 " (" $5 ")"}'
    echo ""
}

# Run main function
main
