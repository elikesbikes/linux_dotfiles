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

MAX_DAYS_SINCE_SUCCESS="${MAX_DAYS_SINCE_SUCCESS:-2}"

HOST="$(hostname -s)"

#####################################
# Notify helper
#####################################
notify() {
  local title="$1"
  local message="$2"
  local priority="${3:-3}"

  printf "%b" "$message" | curl -s \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: idrive,backup" \
    --data-binary @- \
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
# Epoch calculations
#####################################
TODAY_EPOCH="$(date -d 'today 00:00:00' +%s)"
NOW_EPOCH="$(date +%s)"
MAX_SUCCESS_AGE_SEC=$(( MAX_DAYS_SINCE_SUCCESS * 86400 ))

#####################################
# Collect all logs (newest first)
#####################################
mapfile -t ALL_LOGS < <(ls -1 "$LOG_DIR" 2>/dev/null | sort -r)

if (( ${#ALL_LOGS[@]} == 0 )); then
  notify "IDrive Backup ERROR (${HOST})" \
         "No IDrive backup logs found.\nDirectory:\n${LOG_DIR}" \
         5
  exit 1
fi

#####################################
# Find last SUCCESS (any day)
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
         "No SUCCESS backups found in logs." \
         5
  exit 0
fi

LAST_SUCCESS_DATE="$(date -d "@$LAST_SUCCESS_EPOCH" '+%Y-%m-%d %H:%M:%S')"
SUCCESS_AGE_SEC=$(( NOW_EPOCH - LAST_SUCCESS_EPOCH ))

if (( SUCCESS_AGE_SEC > MAX_SUCCESS_AGE_SEC )); then
  AGE_DAYS=$(( SUCCESS_AGE_SEC / 86400 ))
  notify "IDrive Backup ALERT (${HOST})" \
         "Last SUCCESS backup is too old.\n\nLast success:\n${LAST_SUCCESS_DATE}\nAge: ${AGE_DAYS} days\nLog: ${LAST_SUCCESS_LOG}" \
         5
fi

#####################################
# Find today's logs (epoch-based)
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
# No backup today
#####################################
if (( ${#TODAYS_LOGS[@]} == 0 )); then
  LAST_LOG="${ALL_LOGS[0]}"
  LAST_EPOCH="${LAST_LOG%%_*}"
  LAST_STATUS="$(cut -d_ -f2 <<<"$LAST_LOG")"
  LAST_DATE="$(date -d "@$LAST_EPOCH" '+%Y-%m-%d %H:%M:%S')"

  notify "IDrive Backup NOT RUN TODAY (${HOST})" \
         "No IDrive backup ran today.\n\nLast run:\nDate: ${LAST_DATE}\nStatus: ${LAST_STATUS}\nLog: ${LAST_LOG}\n\nLast SUCCESS:\n${LAST_SUCCESS_DATE}" \
         4
  exit 0
fi

#####################################
# Evaluate latest backup today
#####################################
LATEST_TODAY="${TODAYS_LOGS[0]}"
FILE_EPOCH="${LATEST_TODAY%%_*}"
START_TIME="$(date -d "@$FILE_EPOCH" '+%Y-%m-%d %H:%M:%S')"
FINISH_TIME="$(date -d "@$(stat -c %Y "$LOG_DIR/$LATEST_TODAY")" '+%Y-%m-%d %H:%M:%S')"

case "$LATEST_TODAY" in
  *_Running_*)
    exit 0
    ;;

  *_Success_*)
    notify "IDrive Backup SUCCESS (${HOST})" \
           "Backup completed successfully.\n\nStarted : ${START_TIME}\nFinished: ${FINISH_TIME}\n\nLog file:\n${LATEST_TODAY}" \
           2
    ;;

  *_Skipped_*)
    notify "IDrive Backup SKIPPED (${HOST})" \
           "Backup was skipped today.\n\nLog file:\n${LATEST_TODAY}\n\nLast SUCCESS:\n${LAST_SUCCESS_DATE}" \
           3
    ;;

  *_Canceled_*)
    notify "IDrive Backup CANCELED (${HOST})" \
           "Backup was canceled.\n\nStarted : ${START_TIME}\nFinished: ${FINISH_TIME}\n\nLog file:\n${LATEST_TODAY}" \
           5
    ;;

  *)
    notify "IDrive Backup UNKNOWN (${HOST})" \
           "Unrecognized backup state.\n\nLog file:\n${LATEST_TODAY}" \
           4
    ;;
esac
