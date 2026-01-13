#!/bin/bash

# ==============================================================================
# CHANGELOG
# ------------------------------------------------------------------------------
# DATE        | VERSION | AUTHOR             | CHANGE DESCRIPTION
# 2026-01-13  | 2.3.0   | Tars (ELIKESBIKES) | Relocated logs to /var/log/ and
#             |         |                    | standardized logging logic.
# 2026-01-13  | 2.2.0   | Tars (ELIKESBIKES) | Added 'tee' for live output.
# ==============================================================================

# --- Rule 2.2: Load Environment ---
ENV_FILE="$HOME/.unifi_ops.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "CRITICAL ERROR: Environment file $ENV_FILE not found."
    exit 1
fi

VERSION="2.3.0"
# --- Rule 2.5: Compliance - System-level logging ---
LOG_DIR="/var/log/network/unifi"
LOG_FILE="$LOG_DIR/reboot_$(date +%Y%m).log"

# --- Function: Log and Print ---
log_msg() {
    # Ensure directory exists (Rule 2.4: Portability)
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
    echo "[$VERSION] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

notify() {
    local message="$1"
    if [ -n "$NTFY_TOPIC" ]; then
        curl -s -H "Title: Network Maintenance" -d "$message" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
    fi
}

# --- Pre-Flight Checks ---
if ! ssh-add -l > /dev/null 2>&1; then
    log_msg "ERROR: SSH agent empty. Loading key..."
    ssh-add "$UNIFI_SSH_KEY" 2>/dev/null
fi

log_msg "Initiating sequence via Gateway Jump ($GATEWAY_IP)..."

# --- Execution ---
for AP_IP in $UNIFI_DEVICES; do
    # Skip the Gateway as per earlier rules
    [ "$AP_IP" == "$GATEWAY_IP" ] && continue

    log_msg "Targeting Access Point: $AP_IP"

    # SSH via Jump Host (Rule 2.4)
    ssh -i "$UNIFI_SSH_KEY" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -J "$UNIFI_USER@$GATEWAY_IP" \
        "$UNIFI_USER@$AP_IP" "reboot" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        log_msg "SUCCESS: Reboot signaled for $AP_IP."
    else
        log_msg "FAILURE: Could not signal $AP_IP. Review log for details."
    fi
done

log_msg "Sequence Complete."
notify "UniFi AP Reboot Complete
Version: $VERSION
Log: $LOG_FILE"

exit 0