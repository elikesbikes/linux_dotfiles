#!/bin/bash

# ==============================================================================
# CHANGELOG
# ------------------------------------------------------------------------------
# DATE        | VERSION | AUTHOR             | CHANGE DESCRIPTION
# 2026-01-13  | 6.0.0   | Tars (ELIKESBIKES) | Final Pivot: Using sshpass with
#             |         |                    | cleartext password. No SSH keys
#             |         |                    | required for APs.
# ==============================================================================

# --- Rule 2.2: Load Environment ---
ENV_FILE="$HOME/.unifi_ops.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE" || { echo "Env file missing"; exit 1; }

VERSION="6.0.0"
LOG_DIR="/var/log/network/unifi"
LOG_FILE="$LOG_DIR/reboot_$(date +%Y%m).log"

log_msg() {
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
    echo "[$VERSION] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

notify() {
    local message="$1"
    [ -n "$NTFY_TOPIC" ] && curl -s -H "Title: Network Maintenance" -d "$message" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
}

# Ensure variables exist
if [[ -z "$UNIFI_PASS" ]]; then
    log_msg "ERROR: UNIFI_PASS not found in .env file."
    exit 1
fi

log_msg "Initiating Reboot Sequence via Jump Host ($GATEWAY_IP)..."

# --- Execution ---
for IP in $UNIFI_DEVICES; do
    [ "$IP" == "$GATEWAY_IP" ] && continue

    log_msg "Targeting $IP..."

    # sshpass -p: passes the password
    # -o StrictHostKeyChecking=no: ignores finger-print warnings
    # -J: Jumps through the Gateway (using your existing working key)
    sshpass -p "$UNIFI_PASS" ssh -o StrictHostKeyChecking=no \
        -o BatchMode=no \
        -o ConnectTimeout=15 \
        -i "$UNIFI_SSH_KEY" \
        -J "$UNIFI_USER@$GATEWAY_IP" \
        "$UNIFI_USER@$IP" "reboot" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        log_msg "SUCCESS: $IP signaled."
    else
        log_msg "FAILURE: $IP rejected password or timed out."
    fi
done

log_msg "Sequence Complete."
notify "UniFi AP Reboot Complete (v$VERSION)"

exit 0