#!/bin/bash

# ==============================================================================
# CHANGELOG
# ------------------------------------------------------------------------------
# DATE        | VERSION | AUTHOR             | CHANGE DESCRIPTION
# 2026-01-13  | 4.0.0   | Tars (ELIKESBIKES) | PIVOT: Using sshpass with verified
#             |         |                    | credentials. Abandoned PoE & Keys.
#             |         |                    | Retained Gateway Jump for routing.
# ==============================================================================

# --- Rule 2.2: Load Environment ---
ENV_FILE="$HOME/.unifi_ops.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE" || { echo "Env file missing"; exit 1; }

VERSION="4.0.0"
LOG_DIR="/var/log/network/unifi"
LOG_FILE="$LOG_DIR/reboot_$(date +%Y%m).log"

# --- Function: Log and Print (Rule 2.5) ---
log_msg() {
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
    echo "[$VERSION] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

notify() {
    local message="$1"
    [ -n "$NTFY_TOPIC" ] && curl -s -H "Title: UniFi Maintenance" -d "$message" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
}

# --- Rule 1.2: Validate Vars ---
if [[ -z "$UNIFI_PASS" || -z "$GATEWAY_IP" ]]; then
    log_msg "ERROR: UNIFI_PASS or GATEWAY_IP missing in $ENV_FILE"
    exit 1
fi

log_msg "Starting sequence via Gateway Jump ($GATEWAY_IP)..."

# --- Execution (Rule 2.4: Portability) ---
for IP in $UNIFI_DEVICES; do
    # Skip Gateway if it's in the list
    [ "$IP" == "$GATEWAY_IP" ] && continue

    log_msg "Targeting Access Point: $IP"

    # Use sshpass to inject the password into the SSH tunnel
    # Leg 1: Jump to Gateway (using your existing working Key)
    # Leg 2: Hit AP (using the newly discovered Password)
    export SSHPASS="$UNIFI_PASS"
    sshpass -e ssh -o StrictHostKeyChecking=no -o BatchMode=no -o ConnectTimeout=15 \
        -J "$UNIFI_USER@$GATEWAY_IP" \
        "$UNIFI_USER@$IP" "reboot" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        log_msg "SUCCESS: $IP signaled to reboot."
    else
        log_msg "FAILURE: $IP rejected credentials or is unreachable."
    fi
done

log_msg "Sequence Complete."
notify "UniFi AP Reboot Complete (v$VERSION)"

exit 0