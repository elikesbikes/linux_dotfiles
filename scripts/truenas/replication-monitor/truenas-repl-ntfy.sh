#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# TrueNAS SCALE Replication Monitor (REMOTE, LOG-BASED)
# ============================================================
# - Runs remotely (no SSH to NAS)
# - Uses job logs as the authoritative source of truth
# - Sends human-readable ntfy notifications
# - One message per replication job per day
# - Separate alert if replication did not run
# - Env file resolved internally (cron stays clean)
# ============================================================

# ------------------------------------------------------------
# Environment file (canonical location)
# ------------------------------------------------------------
ENV_FILE="${ENV_FILE:-$HOME/.truenas-repl-ntfy.env}"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

need curl
need jq
need date
need sed

[[ -f "$ENV_FILE" ]] || die "Env file not found: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

# ------------------------------------------------------------
# Required configuration
# ------------------------------------------------------------
: "${TRUENAS_URL:?Missing TRUENAS_URL in $ENV_FILE}"
: "${TRUENAS_API_KEY:?Missing TRUENAS_API_KEY in $ENV_FILE}"
: "${NTFY_URL:?Missing NTFY_URL in $ENV_FILE}"
: "${NTFY_TOPIC:?Missing NTFY_TOPIC in $ENV_FILE}"

# ------------------------------------------------------------
# Optional configuration
# ------------------------------------------------------------
VERIFY_TLS="${VERIFY_TLS:-true}"
TIMEOUT_SEC="${TIMEOUT_SEC:-20}"
NTFY_TAGS="${NTFY_TAGS:-truenas,replication}"

curl_opts=(-sS --max-time "$TIMEOUT_SEC")
[[ "$VERIFY_TLS" != "true" ]] && curl_opts+=(-k)

api() {
  curl "${curl_opts[@]}" \
    -H "Authorization: Bearer $TRUENAS_API_KEY" \
    -H "Accept: application/json" \
    "$1"
}

notify() {
  curl -sS \
    -H "Title: $1" \
    -H "Priority: $3" \
    -H "Tags: $NTFY_TAGS" \
    -d "$2" \
    "$NTFY_URL/$NTFY_TOPIC" >/dev/null
}

fmt_epoch_ms() {
  local ms="$1"
  [[ -z "$ms" || "$ms" == "null" ]] && echo "N/A" && return
  date -d "@$(( ms / 1000 ))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A"
}

today_date="$(date '+%Y-%m-%d')"
now="$(date '+%Y-%m-%d %H:%M:%S')"

# ------------------------------------------------------------
# Fetch all replication jobs
# ------------------------------------------------------------
jobs="$(api "$TRUENAS_URL/api/v2.0/core/get_jobs")"

replication_jobs="$(jq '
  [
    .[]
    | select(.method=="replication.run")
    | select(.time_started != null)
  ]
' <<<"$jobs")"

jobs_today="$(jq --arg today "$today_date" '
  [
    .[]
    | select(
        (.time_started."$date" / 1000 | strftime("%Y-%m-%d")) == $today
      )
  ]
' <<<"$replication_jobs")"

job_count_today="$(jq length <<<"$jobs_today")"

# ------------------------------------------------------------
# If no replication ran today → alert
# ------------------------------------------------------------
if [[ "$job_count_today" -eq 0 ]]; then
  notify \
    "TrueNAS Replication — DID NOT RUN" \
    "Job status: DID NOT RUN
Date: $today_date
Checked at: $now" \
    4
  exit 0
fi

# ------------------------------------------------------------
# Process each replication job that ran today
# ------------------------------------------------------------
jq -c '.[]' <<<"$jobs_today" | while read -r job; do
  job_id="$(jq -r '.id' <<<"$job")"
  job_state="$(jq -r '.state' <<<"$job")"

  start_ms="$(jq -r '.time_started."$date"' <<<"$job")"
  end_ms="$(jq -r '.time_finished."$date" // empty' <<<"$job")"

  start_time="$(fmt_epoch_ms "$start_ms")"
  end_time="$(fmt_epoch_ms "$end_ms")"

  # --------------------------------------------------------
  # Fetch job log (authoritative source)
  # --------------------------------------------------------
  log_text="$(api "$TRUENAS_URL/api/v2.0/core/job_log?id=$job_id")"

  # --------------------------------------------------------
  # Extract replication task name (best effort)
  # --------------------------------------------------------
  task_name="$(
    echo "$log_text" \
    | sed -n "s/.*replication task '\([^']*\)'.*/\1/p" \
    | head -n1
  )"

  if [[ -z "$task_name" ]]; then
    task_name="$(
      echo "$log_text" \
      | sed -n "s/.*replication_task__\(task_[0-9]\+\).*/\1/p" \
      | head -n1
    )"
  fi

  [[ -z "$task_name" ]] && task_name="(not present in job log)"

  # --------------------------------------------------------
  # Extract dataset mapping (best effort)
  # --------------------------------------------------------
  dataset_info="$(
    echo "$log_text" \
    | sed -n "s/.*doing push from '\([^']*\)' to '\([^']*\)'.*/\1 → \2/p" \
    | head -n1
  )"

  if [[ -z "$dataset_info" ]]; then
    dataset_info="$(
      echo "$log_text" \
      | sed -n "s/.*from '\([^']*\)' to '\([^']*\)'.*/\1 → \2/p" \
      | head -n1
    )"
  fi

  [[ -z "$dataset_info" ]] && dataset_info="(not present in job log)"

  # --------------------------------------------------------
  # Build human-readable message
  # --------------------------------------------------------
  base_msg="Job ID: $job_id
Replication task: $task_name
Datasets: $dataset_info
Job status: $job_state
Start time: $start_time
End time: $end_time
Checked at: $now"

  # --------------------------------------------------------
  # Send notifications
  # --------------------------------------------------------
  if [[ "$job_state" == "RUNNING" ]]; then
    notify "TrueNAS Replication — RUNNING" "$base_msg" 2
    continue
  fi

  if echo "$log_text" | grep -qiE 'error|failed|traceback'; then
    notify \
      "TrueNAS Replication — FAILED" \
      "$base_msg

Last log lines:
$(echo "$log_text" | tail -n 20)" \
      5
  else
    notify "TrueNAS Replication — SUCCESSFUL" "$base_msg" 3
  fi
done
