#!/usr/bin/env bash
set -euo pipefail

#####################################
# Optional env override (HOME only)
#####################################
ENV_FILE="${ENV_FILE:-/home/ecloaiza/.idrive.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

#####################################
# Config
#####################################
LOG_DIR="${LOG_DIR:-/opt/IDriveForLinux/idriveIt/user_profile/ecloaiza/ecloaiza@hotmail.com/Backup/DefaultBackupSet/LOGS}"

NTFY_URL="${NTFY_URL:-https://ntfy.home.elikesbikes.com}"
NTFY_TOPIC="${NTFY_TOPIC:-backups}"

# Alert if last SUCCESS is older than N days
MAX_DAYS_SINCE_SUCCESS="${MAX_DAYS_SINCE_SUCCESS:-2}"

HOST="$(hostname -s)"

#####################################
# Notify helper
#####################################
notify() {
  local title="$1"
  local message="$2"
  local priority="${3:-3}"

  curl -s \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: idrive,backup" \
    -d "${message}" \
    "${NTFY_URL}/${NTFY_TOPIC}" >/dev/null
}

#####################################
# Sanity check
#####################################
if [[ ! -d "$LOG_DIR" ]]; then
  notify "IDrive Monitor ERROR (${HOST})" \
         "Log directory not found:\n${LOG_DIR}" \
         5
  exit 1
fi

#####################################
# Epoch boundaries
#####################################
TODAY_EPOCH="$(date -d 'today 00:00:00' +%s)"
NOW_EPOCH="$(date +%s)"
MAX_SUCCESS_AGE_SEC=$(( MAX_DAYS_SINCE_SUCCESS * 86400 ))

#####################################
# Collect all logs (sorted newest first)
#####################################
mapfile -t ALL_LOGS < <(ls -1 "$LOG_DIR" 2>/dev/null | sort -r)

if (( ${#ALL_LOGS[@]} == 0 )); then
  notify "IDrive Backup ERROR (${HOST})" \
         "No IDrive backup logs found at all.\nDirectory:\n${LOG_DIR}" \
         5
  exit 1
fi

#####################################
# Find most recent SUCCESS log (any day)
#####################################
LAST_SUCCESS_LOG=""
LAST_SUCCESS_EPOCH=""

for f in "${ALL_LOGS[@]}"; do
  case "$f" in
    *_Success_*)
      FILE_EPOCH="${f%%_*}"
      if [[ "$FILE_EPOCH" =~ ^[0-9]+$ ]]; then
        LAST_SUCCESS_LOG="$f"
        LAST_SUCCESS_EPOCH="$FILE_EPOCH"
        break
      fi
      ;;
  esac
done

if [[ -z "$LAST_SUCCESS_LOG" ]]; then
  notify "IDrive Backup ALERT (${HOST})" \
         "No SUCCESS backups found in logs.\nDirectory:\n${LOG_DIR}" \
         5
  exit 0
fi

LAST_SUCCESS_DATE="$(date -d "@$LAST_SUCCESS_EPOCH" '+%Y-%m-%d %H:%M:%S')"
SUCCESS_AGE_SEC=$(( NOW_EPOCH - LAST_SUCCESS_EPOCH ))

if (( SUCCESS_AGE_SEC > MAX_SUCCESS_AGE_SEC )); then
  AGE_DAYS=$(( SUCCESS_AGE_SEC / 86400 ))
  notify "IDrive Backup ALERT (${HOST})" \
         "Last SUCCESS backup is too old.\n\nLast success: ${LAST_SUCCESS_DATE}\nAge: ${AGE_DAYS} days\nLog: ${LAST_SUCCESS_LOG}" \
         5
  # keep going — we can also report today's status below
fi

#####################################
# Find today's logs (based on epoch)
#####################################
TODAYS_LOGS=()

for f in "${ALL_LOGS[@]}"; do
  FILE_EPOCH="${f%%_*}"
  [[ "$FILE_EPOCH" =~ ^[0-9]+$ ]] || continue
  if (( FILE_EPOCH >= TODAY_EPOCH )); then
    TODAYS_LOGS+=("$f")
  fi
done

#####################################
# No backup today → report last run
#####################################
if (( ${#TODAYS_LOGS[@]} == 0 )); then
  LAST_LOG="${ALL_LOGS[0]}"
  LAST_EPOCH="${LAST_LOG%%_*}"
  LAST_STATUS="$(echo "$LAST_LOG" | cut -d_ -f2)"
  LAST_DATE="$(date -d "@$LAST_EPOCH" '+%Y-%m-%d %H:%M:%S')"

  notify "IDrive Backup NOT RUN TODAY (${HOST})" \
         "No IDrive backup ran today.\n\nLast run:\nDate: ${LAST_DATE}\nStatus: ${LAST_STATUS}\nLog: ${LAST_LOG}\n\nLast SUCCESS:\n${LAST_SUCCESS_DATE}\nLog: ${LAST_SUCCESS_LOG}" \
         4
  exit 0
fi

#####################################
# Evaluate latest backup today
#####################################
LATEST_TODAY="${TODAYS_LOGS[0]}"

case "$LATEST_TODAY" in
  *_Running_*)
    exit 0
    ;;

  *_Success_*)
    notify "IDrive Backup SUCCESS (${HOST})" \
           "Latest backup today completed successfully.\n\nLog file:\n${LATEST_TODAY}" \
           2
    ;;

  *_Skipped_*)
    notify "IDrive Backup SKIPPED (${HOST})" \
           "Backup was skipped today.\n\nLog file:\n${LATEST_TODAY}\n\nLast SUCCESS:\n${LAST_SUCCESS_DATE}\nLog: ${LAST_SUCCESS_LOG}" \
           3
    ;;

  *_Canceled_*)
    notify "IDrive Backup CANCELED (${HOST})" \
           "Backup was canceled today.\n\nLog file:\n${LATEST_TODAY}\n\nLast SUCCESS:\n${LAST_SUCCESS_DATE}\nLog: ${LAST_SUCCESS_LOG}" \
           5
    ;;

  *)
    notify "IDrive Backup UNKNOWN (${HOST})" \
           "Unrecognized backup state today.\n\nLog file:\n${LATEST_TODAY}\n\nLast SUCCESS:\n${LAST_SUCCESS_DATE}\nLog: ${LAST_SUCCESS_LOG}" \
           4
    ;;
esac
