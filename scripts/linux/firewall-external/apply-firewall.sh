#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SCRIPT="${SCRIPT_DIR}/firewall-apply-rules.sh"
LOGFILE="/var/log/firewall-external.log"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

log() {
  echo "[[apply-firewall]] $1"
}

rotate_log() {
  if [[ -f "$LOGFILE" ]] && [[ "$(stat -c%s "$LOGFILE")" -gt 1000000 ]]; then
    mv "$LOGFILE" "${LOGFILE}.1"
    touch "$LOGFILE"
  fi
}

rotate_log
exec >>"$LOGFILE" 2>&1

log "===== apply-firewall.sh run started ====="

# Resolve home IP via DDNS hostname
DDNS_HOST="router.elikesbikes.com"
log "Resolving DDNS host: $DDNS_HOST ..."
HOME_IP="$(getent ahostsv4 "$DDNS_HOST" | awk '{print $1; exit}')"

if [[ -z "$HOME_IP" ]]; then
  log "ERROR: Failed to resolve $DDNS_HOST"
  exit 1
fi

log "Resolved DDNS Host: $DDNS_HOST → $HOME_IP"

STATE_FILE="/var/run/home_ip.txt"
LAST_IP=""

if [[ -f "$STATE_FILE" ]]; then
  LAST_IP="$(cat "$STATE_FILE")"
fi

if [[ "$HOME_IP" != "$LAST_IP" || "$FORCE" -eq 1 ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    log "FORCE MODE ACTIVE → Applying firewall rules regardless of IP change."
  else
    log "HOME IP CHANGE DETECTED! Old: '$LAST_IP' → New: '$HOME_IP'"
  fi

  if [[ ! -x "$RULES_SCRIPT" ]]; then
    log "ERROR: firewall-apply-rules.sh not found or not executable"
    exit 1
  fi

  log "Applying firewall rules with HOME_IP=$HOME_IP ..."
  "$RULES_SCRIPT" "$HOME_IP"

  echo "$HOME_IP" > "$STATE_FILE"
  log "Firewall rules updated successfully."

else
  log "No IP change detected (still $HOME_IP). Skipping firewall rules apply."
fi

log "===== apply-firewall.sh run finished ====="
