#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/ddns-update.log"

# --- Log rotation (simple, safe) ---
if [ -f "$LOGFILE" ] && [ "$(stat -c%s "$LOGFILE")" -gt 1000000 ]; then
  mv "$LOGFILE" "${LOGFILE}.1"
  touch "$LOGFILE"
fi

{
  echo "==========================================================="
  echo "[ddns-update] Run started: $(date '+%Y-%m-%d %H:%M:%S')"

  # Force ddclient to update DNS
  if ddclient -force -verbose; then
    echo "[ddns-update] SUCCESS: ddclient updated DNS."
  else
    echo "[ddns-update] ERROR: ddclient failed!"
  fi

  echo "[ddns-update] Run finished: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "==========================================================="
  echo
} >>"$LOGFILE" 2>&1
