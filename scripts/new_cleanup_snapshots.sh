#!/bin/sh
# cleanup_snapshots.sh - Removes stuck snapshots ONLY if no backup is running.

SNAPSHOT_DIR="/mnt/urbackup_snaps"

# --- SAFETY CHECK 1: Are the scripts running? ---
# If the create or remove scripts are currently executing, do not interfere.
if pgrep -f "dattobd_create_snapshot" > /dev/null || pgrep -f "dattobd_remove_snapshot" > /dev/null; then
    echo "[INFO] Snapshot scripts are currently running. Skipping cleanup to avoid conflicts."
    exit 0
fi

# --- SAFETY CHECK 2: Are files being accessed? ---
# If any process (like UrBackup) has a file open inside the snapshot directory, a backup is active.
# We use lsof +D to check the directory tree recursively.
if lsof +D "$SNAPSHOT_DIR" > /dev/null 2>&1; then
    echo "[INFO] Active backup detected (files are open in $SNAPSHOT_DIR). Skipping cleanup."
    exit 0
fi

# --- CLEANUP PHASE ---
# If we get here, nothing is touching the snapshots. Anything mounted is "stuck".

echo "[START] No active backups detected. Checking for stuck snapshots..."

# Find all datto devices mounted under the snapshot dir
MOUNTED_DEVICES=$(lsblk -n -o NAME,MOUNTPOINT | grep "$SNAPSHOT_DIR" | grep "datto" || true)

if [ -z "$MOUNTED_DEVICES" ]; then
    # Optional: echo "System is clean."
    exit 0
fi

echo "$MOUNTED_DEVICES" | while read -r DEVICE MOUNTPOINT; do
    NUM=$(echo "$DEVICE" | sed 's/[^0-9]*//g')
    
    if [ -n "$NUM" ]; then
        echo "--- Cleaning up stuck snapshot: $DEVICE ($NUM) ---"
        
        # 1. Force lazy unmount
        umount -l "$MOUNTPOINT" || true
        
        # 2. Destroy the device
        dbdctl destroy "$NUM" || true
        
        # 3. Clean up directory
        rmdir "$MOUNTPOINT" || true
        
        echo "Cleanup complete for $DEVICE."
    fi
done
