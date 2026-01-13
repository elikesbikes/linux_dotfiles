#!/bin/bash

# ==============================================================================
# CHANGELOG
# ------------------------------------------------------------------------------
# DATE        | VERSION | AUTHOR             | CHANGE DESCRIPTION
# 2026-01-13  | 2.4.0   | Tars (ELIKESBIKES) | Switched to explicit identity 
#             |         |                    | mapping to bypass agent issues.
#             |         |                    | Added strict variable validation.
# 2026-01-13  | 2.3.0   | Tars (ELIKESBIKES) | Relocated logs to /var/log/.
# ==============================================================================

# --- Rule 2.2: Load Environment ---
ENV_FILE="$HOME/.unifi_ops.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "CRITICAL ERROR: Environment file $ENV_FILE not found."
    exit 1
fi

VERSION="2.4.0"
LOG_DIR="/var/log/network/unifi"
LOG_FILE="$LOG_DIR/reboot_$(date +%Y%m).log"

# --- Function: Log and Print ---
log_msg() {
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
    echo "[$VERSION] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# --- Rule 1.2: Validate Data before Execution ---
if [[ -z "$GATEWAY_IP" || -z "$UNIFI_DEVICES" || -z "$UNIFI_SSH_KEY" ]]; then
    log_msg "ERROR: Missing required variables in $ENV_FILE. Check GATEWAY_IP and UNIFI_DEVICES."
    exit 1
fi

notify() {
    local message="$1"
    if [ -n "$NTFY_TOPIC" ]; then
        curl -s -H "Title: Network Maintenance" -d "$message" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
    fi
}

log_msg "Initiating sequence via Gateway Jump ($GATEWAY_IP)..."

# --- Execution ---
for AP_IP in $UNIFI_DEVICES; do
    [ "$AP_IP" == "$GATEWAY_IP" ] && continue

    log_msg "Targeting Access Point: $AP_IP"

    # Rule 2.4: Portability & Reliability
    # Using ProxyCommand instead of -J for better control over identity passing
    ssh -o "ProxyCommand=ssh -i $UNIFI_SSH_KEY -o StrictHostKeyChecking=no -W %h:%p $UNIFI_USER@$GATEWAY_IP" \
        -i "$UNIFI_SSH_KEY" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=15 \
        "$UNIFI_USER@$AP_IP" "reboot" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        log_msg "SUCCESS: Reboot signaled for $AP_IP."
    else
        log_msg "FAILURE: Could not signal $AP_IP. Check SSH key access from Gateway to AP."
    fi
done

log_msg "Sequence Complete."
notify "UniFi AP Reboot Complete
Version: $VERSION
Log: $LOG_FILE"

exit 0