#!/bin/bash

LOG_TAG="[[apply-firewall]]"
STATE_FILE="/var/run/home_ip.txt"
DDNS_HOST="router.elikesbikes.com"
FIREWALL_SCRIPT="/home/ecloaiza/scripts/linux/firewall-apply-rules.sh"
FORCE=0

# --- Parse arguments ---
for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=1
            ;;
    esac
done

echo "${LOG_TAG} ===== apply-firewall.sh run started ====="
echo "${LOG_TAG} Resolving DDNS host: ${DDNS_HOST} ..."

CURRENT_IP=$(dig +short ${DDNS_HOST} | tail -n 1)

if [[ -z "$CURRENT_IP" ]]; then
    echo "${LOG_TAG} ERROR: Could not resolve DDNS!"
    exit 1
fi

echo "${LOG_TAG} Resolved DDNS Host: ${DDNS_HOST} → ${CURRENT_IP}"

# Load stored IP
OLD_IP=""
[ -f "$STATE_FILE" ] && OLD_IP=$(cat "$STATE_FILE")

# Force mode behavior
if [[ "$FORCE" -eq 1 ]]; then
    echo "${LOG_TAG} FORCE MODE ACTIVE → Applying firewall rules regardless of IP change."
else
    if [[ "$OLD_IP" == "$CURRENT_IP" ]]; then
        echo "${LOG_TAG} No IP change detected (still ${CURRENT_IP}). Skipping firewall rules apply."
        echo "${LOG_TAG} ===== apply-firewall.sh run finished ====="
        exit 0
    fi
    echo "${LOG_TAG} HOME IP CHANGE DETECTED! Old: '${OLD_IP}' → New: '${CURRENT_IP}'"
fi

# Save new IP
echo "$CURRENT_IP" > "$STATE_FILE"

echo "${LOG_TAG} Applying firewall rules with HOME_IP=${CURRENT_IP} ..."

# >>> CALL FIREWALL SCRIPT WITH ARGUMENT <<<
if ! bash "$FIREWALL_SCRIPT" "$CURRENT_IP"; then
    echo "${LOG_TAG} ERROR: firewall-apply-rules.sh failed."
    echo "${LOG_TAG} ===== apply-firewall.sh run finished (ERROR) ====="
    exit 1
fi

echo "${LOG_TAG} Firewall rules updated successfully."
echo "${LOG_TAG} ===== apply-firewall.sh run finished ====="
exit 0

