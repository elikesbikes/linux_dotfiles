#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/ddns-update.log"
NTFY_URL="https://ntfy.home.elikesbikes.com/networking"
HOSTNAME="$(hostname)"

# --- Log rotation (simple, safe) ---
if [ -f "$LOGFILE" ] && [ "$(stat -c%s "$LOGFILE")" -gt 1000000 ]; then
  mv "$LOGFILE" "${LOGFILE}.1"
  touch "$LOGFILE"
fi

log() {
  echo "[ddns-update] $1"
}

notify() {
  local title="$1"
  local message="$2"

  curl -fsS \
    -H "Title: $title" \
    -H "Tags: network,ddns" \
    -H "Priority: default" \
    -d "$message" \
    "$NTFY_URL" >/dev/null 2>&1 || true
}

{
  echo "==========================================================="
  log "Run started: $(date '+%Y-%m-%d %H:%M:%S')"

  if ddclient -force -verbose; then
    log "SUCCESS: ddclient updated DNS."

    notify \
      "DDNS Update Success ($HOSTNAME)" \
      "ddclient ran successfully on $HOSTNAME at $(date '+%Y-%m-%d %H:%M:%S')."
  else
    log "ERROR: ddclient failed!"

    notify \
      "DDNS Update FAILED ($HOSTNAME)" \
      "ddclient FAILED on $HOSTNAME at $(date '+%Y-%m-%d %H:%M:%S'). Check $LOGFILE."
  fi

  log "Run finished: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "==========================================================="
  echo
} >>"$LOGFILE" 2>&1
