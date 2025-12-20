#!/bin/bash
# cleanup_snapshots.sh - Robust cleanup for UrBackup/dattobd
# Handles mounted snapshots, zombie devices, and locked COW files.

SNAPSHOT_DIR="/mnt/urbackup_snaps"

# --- PHASE 1: SAFETY CHECKS ---
# If the backup scripts are running, DO NOT TOUCH ANYTHING.
if pgrep -f "dattobd_create_snapshot" > /dev/null || pgrep -f "dattobd_remove_snapshot" > /dev/null; then
    echo "[INFO] Backup scripts are currently running. Skipping cleanup to avoid corruption."
    exit 0
fi

# If files are open in the snapshot directory, a backup is active.
if command -v lsof > /dev/null; then
    if lsof +D "$SNAPSHOT_DIR" > /dev/null 2>&1; then
        echo "[INFO] Active backup detected (files open). Skipping cleanup."
        exit 0
    fi
else
    echo "[WARN] 'lsof' not found. Skipping open file check."
fi

echo "[START] System appears idle. Starting deep cleanup..."

# --- PHASE 2: DEVICE CLEANUP ---
# We iterate through potential datto devices (0-9) to catch "zombies" that aren't mounted.
for i in {0..9}; do
    DEV_PATH="/dev/datto$i"

    # Check if the device exists (block device)
    if [ -b "$DEV_PATH" ]; then
        echo "Found active device: $DEV_PATH"

        # 1. Force Lazy Unmount (if mounted)
        # We try to unmount anywhere it might be mounted
        MOUNTPOINTS=$(findmnt -n -o TARGET "$DEV_PATH")
        for MP in $MOUNTPOINTS; do
            echo "  - Unmounting from $MP..."
            umount -l "$MP" || true
        done

        # 2. Destroy the device
        echo "  - Destroying datto device $i..."
        if dbdctl destroy "$i"; then
            echo "    Success."
        else
            echo "    Failed to destroy $i (might be busy). Retrying in 2s..."
            sleep 2
            dbdctl destroy "$i" || echo "    Still failed to destroy $i."
        fi
    fi
done

# --- PHASE 3: FILE CLEANUP (The "Invalid Argument" Fix) ---
# Old COW files often get stuck with the 'immutable' attribute, preventing deletion.
echo "Cleaning up stale Copy-On-Write files..."

# Function to unlock and delete
cleanup_cow_files() {
    local SEARCH_DIR="$1"
    # Find files named .datto_cow_*
    find "$SEARCH_DIR" -maxdepth 1 -name ".datto_cow_*" 2>/dev/null | while read -r file; do
        echo "  - Removing $file"
        chattr -i "$file" 2>/dev/null  # Unlock the file
        rm -f "$file"                  # Delete the file
    done
}

# Check root and boot directories
cleanup_cow_files "/"
cleanup_cow_files "/boot"
cleanup_cow_files "/boot/efi"

# --- PHASE 4: DIRECTORY CLEANUP ---
echo "Cleaning up empty mount directories..."
# Only delete empty directories inside the snapshot folder
find "$SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null

echo "[DONE] Cleanup complete."
