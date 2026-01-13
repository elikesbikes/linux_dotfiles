#!/bin/bash

# ==============================================================================
# CHANGELOG
# ------------------------------------------------------------------------------
# DATE        | VERSION | AUTHOR             | CHANGE DESCRIPTION
# 2026-01-13  | 7.0.0   | Tars (ELIKESBIKES) | PIVOT: Corrected username to 
#             |         |                    | 'ecloaiza' and switched to 
#             |         |                    | direct SSH (removed Jump Host).
# ==============================================================================

# --- Rule 2.2: Load Environment ---
ENV_FILE="$HOME/.unifi_ops.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE" || { echo "Env file missing"; exit 1; }

VERSION="7.0.0"
LOG_DIR="/var/log/network/unifi"
LOG_FILE="$LOG_DIR/reboot_$(date +%Y%m).log"

log_msg() {
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
    echo "[$VERSION] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

notify() {
    local message="$1"
    [ -n "$NTFY_TOPIC" ] && curl -s -H "Title: AP Reboot" -d "$message" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
}

log_msg "Initiating Direct Reboot Sequence (v$VERSION)..."

# --- Execution ---
for IP in $UNIFI_DEVICES; do
    # Skip Gateway if necessary, though direct SSH to APs is the goal
    [ "$IP" == "192.168.5.1" ] && continue

    log_msg "Targeting $IP as user $UNIFI_USER..."

    # Direct SSH using sshpass and the verified username/password
    sshpass -p "$UNIFI_PASS" ssh -o StrictHostKeyChecking=no \
        -o BatchMode=no \
        -o ConnectTimeout=10 \
        "$UNIFI_USER@$IP" "reboot" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        log_msg "SUCCESS: $IP rebooted."
    else
        log_msg "FAILURE: $IP rejected $UNIFI_USER. Check credentials."
    fi
done

log_msg "Sequence Complete."
notify "UniFi AP Reboot Complete (v$VERSION)"