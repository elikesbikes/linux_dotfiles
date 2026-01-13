#!/bin/bash

# ==============================================================================
# CHANGELOG
# ------------------------------------------------------------------------------
# DATE        | VERSION | AUTHOR             | CHANGE DESCRIPTION
# 2026-01-13  | 2.1.0   | Tars (ELIKESBIKES) | Switched to SSH Jump Host pattern.
#             |         |                    | Uses Agent Forwarding to bypass 
#             |         |                    | Gateway password requirement.
# 2026-01-13  | 2.0.0   | Tars (ELIKESBIKES) | Major Pivot: Gateway as Jump Host.
# ==============================================================================

# --- Rule 2.2: Load Environment Variables ---
ENV_FILE="$HOME/.unifi_ops.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "ERROR: Environment file $ENV_FILE not found."
    exit 1
fi

VERSION="2.1.0"
LOG_DIR="/home/ecloaiza/scripts/network/unifi/logs"
LOG_FILE="$LOG_DIR/reboot_$(date +%Y%m).log"
mkdir -p "$LOG_DIR"

notify() {
    local message="$1"
    if [ -n "$NTFY_TOPIC" ]; then
        curl -H "Title: Jump-Host Reboot" -d "$message" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
    fi
}

START_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "[$START_TIME] [v$VERSION] Initiating Jump-Host sequence via $GATEWAY_IP..." >> "$LOG_FILE"

# --- Execution ---
for AP_IP in $UNIFI_DEVICES; do
    if [ "$AP_IP" == "$GATEWAY_IP" ]; then continue; fi

    echo "[$AP_IP] Attempting reboot via Gateway jump..." >> "$LOG_FILE"

    # Rule 2.4: Portability. 
    # -J (Jump): Connects to Gateway, then tunnels to the AP.
    # -o BatchMode: Prevents hanging if the AP rejects the key.
    ssh -i "$UNIFI_SSH_KEY" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -J "$UNIFI_USER@$GATEWAY_IP" \
        "$UNIFI_USER@$AP_IP" "reboot" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        echo "[$AP_IP] Success: Reboot triggered." >> "$LOG_FILE"
    else
        echo "[$AP_IP] FAILURE: Key rejected by AP or AP unreachable from Gateway." >> "$LOG_FILE"
    fi
done

END_TIME=$(date "+%Y-%m-%d %H:%M:%S")
notify "UniFi AP Reboot Complete
Mode: Jump-Host (v$VERSION)
End: $END_TIME"

exit 0