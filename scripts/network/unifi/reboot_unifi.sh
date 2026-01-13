#!/bin/bash

# ==============================================================================
# CHANGELOG
# ------------------------------------------------------------------------------
# DATE        | VERSION | AUTHOR             | CHANGE DESCRIPTION
# 2026-01-13  | 1.1.0   | Tars (ELIKESBIKES) | Updated script path to 
#             |         |                    | /scripts/network/unifi/.
# 2026-01-13  | 1.0.0   | Tars (ELIKESBIKES) | Initial release. 
# ==============================================================================

# --- Rule 2.2: Load Environment Variables ---
ENV_FILE="$HOME/.unifi_ops.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "ERROR: Environment file $ENV_FILE not found."
    exit 1
fi

# --- Configuration & Rule 2.5: Logging ---
VERSION="1.1.0"
LOG_DIR="/home/ecloaiza/scripts/network/unifi/logs"
LOG_FILE="$LOG_DIR/reboot_$(date +%Y%m).log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# --- Notification Function (Rule 5) ---
notify() {
    local message="$1"
    if [ -n "$NTFY_TOPIC" ]; then
        curl -H "Title: UniFi Network Alert" -d "$message" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
    fi
}

# --- Start Logic ---
START_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "[$START_TIME] [v$VERSION] Starting reboot sequence..." >> "$LOG_FILE"

notify "UniFi Reboot Sequence Initiated
Start: $START_TIME
Host: $(hostname)
Version: $VERSION"

# --- Execution ---
# UNIFI_DEVICES must be defined in .unifi_ops.env
for IP in $UNIFI_DEVICES; do
    
    # Rule 1.2: Validate reachability before attempting command
    if ping -c 1 -W 2 "$IP" > /dev/null 2>&1; then
        echo "[$IP] Host reachable. Executing reboot..." >> "$LOG_FILE"
        
        # Rule 2.4: Portability - Identity file and user from ENV
        ssh -i "$UNIFI_SSH_KEY" \
            -o ConnectTimeout=10 \
            -o StrictHostKeyChecking=no \
            -o BatchMode=yes \
            "root@$IP" "reboot"
        
        if [ $? -eq 0 ]; then
            echo "[$IP] Success: Reboot command accepted." >> "$LOG_FILE"
        else
            echo "[$IP] ERROR: SSH command failed. Check SSH key/permissions." >> "$LOG_FILE"
        fi
    else
        echo "[$IP] CRITICAL: Host unreachable via ping. Skipping." >> "$LOG_FILE"
    fi
done

# --- End Logic ---
END_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "[$END_TIME] [v$VERSION] Reboot sequence complete." >> "$LOG_FILE"

notify "UniFi Reboot Sequence Complete
Start: $START_TIME
End: $END_TIME"

exit 0