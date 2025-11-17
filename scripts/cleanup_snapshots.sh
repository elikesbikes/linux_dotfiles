#!/bin/sh
set -e

echo "Looking for stuck datto snapshots..."

# Find all datto devices mounted under /mnt/urbackup_snaps
# We use 'grep datto' to be safe, but '/mnt/urbackup_snaps' is more specific
# The '|| true' at the end ensures the script doesn't exit if grep finds nothing
MOUNTED_DEVICES=$(lsblk -n -o NAME,MOUNTPOINT | grep "/mnt/urbackup_snaps" | grep "datto" || true)

if [ -z "$MOUNTED_DEVICES" ]; then
    echo "No stuck datto snapshots found. System is clean."
    exit 0
fi

echo "Found stuck snapshots:"
echo "$MOUNTED_DEVICES"
echo ""

# Loop through each line of the output
echo "$MOUNTED_DEVICES" | while read -r DEVICE MOUNTPOINT; do
    
    # Extract the number from the device name (e.g., "0" from "datto0")
    NUM=$(echo "$DEVICE" | sed 's/[^0-9]*//g')
    
    if [ -n "$NUM" ]; then
        echo "--- Cleaning up $DEVICE ($NUM) ---"
        
        # 1. Force unmount the snapshot
        echo "Unmounting $MOUNTPOINT..."
        sudo umount -l "$MOUNTPOINT" || echo "Unmount failed (already unmounted?)"
        
        # 2. Destroy the snapshot
        echo "Destroying snapshot $NUM..."
        sudo dbdctl destroy "$NUM" || echo "Destroy failed (already destroyed?)"
        
        # 3. Clean up the directory
        sudo rmdir "$MOUNTPOINT" || echo "rmdir failed (already removed?)"
        
        echo "Cleanup for $DEVICE complete."
    fi
done

echo "All stuck snapshots have been cleaned up."
