#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Configuration
# ==================================================

# Proxmox connection (use the hostname that works with BatchMode!)
PROXMOX_HOST="proxmox-prod-1s"
PROXMOX_USER="root"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"

# ntfy
NTFY_URL="https://ntfy.home.elikesbikes.com"
NTFY_TOPIC="backups"

# ==================================================
# Helper: run command on Proxmox
# ==================================================
remote() {
  ssh $SSH_OPTS "${PROXMOX_USER}@${PROXMOX_HOST}" "$@"
}

# ==================================================
# Calculate today's start (epoch) ON PROXMOX
# ==================================================
TODAY_START=$(remote "date -d 'today 00:00' +%s")

# ==================================================
# Fetch today's vzdump job (authoritative source)
# ==================================================
TASK_JSON=$(remote "pvesh get /cluster/tasks --output-format json")

TASK=$(echo "$TASK_JSON" | jq -r --argjson start "$TODAY_START" '
  map(select(.type == "vzdump" and .starttime >= $start))
  | sort_by(.starttime)
  | last
')

TASK_UPID=$(echo "$TASK" | jq -r '.upid')
TASK_NODE=$(echo "$TASK" | jq -r '.node')
TASK_STATUS=$(echo "$TASK" | jq -r '.status')
START_EPOCH=$(echo "$TASK" | jq -r '.starttime')
END_EPOCH=$(echo "$TASK" | jq -r '.endtime // empty')

# ==================================================
# If no backup job ran today → notify
# ==================================================
if [[ -z "$TASK_UPID" || "$TASK_UPID" == "null" ]]; then
  curl -s -X POST "$NTFY_URL/$NTFY_TOPIC" \
    -H "Title: Proxmox Backup DID NOT RUN" \
    -H "Priority: high" \
    -d "❌ No Proxmox backup job was executed today on $PROXMOX_HOST"
  exit 1
fi

# ==================================================
# Format times (locally)
# ==================================================
START_TIME=$(date -d "@$START_EPOCH" "+%Y-%m-%d %H:%M:%S")

if [[ -n "$END_EPOCH" ]]; then
  END_TIME=$(date -d "@$END_EPOCH" "+%Y-%m-%d %H:%M:%S")
  DURATION=$((END_EPOCH - START_EPOCH))
  DURATION_FMT=$(printf '%02dh:%02dm:%02ds' \
    $((DURATION/3600)) \
    $((DURATION%3600/60)) \
    $((DURATION%60)))
else
  END_TIME="unknown"
  DURATION_FMT="unknown"
fi

# ==================================================
# Notify result (NO ATTACHMENTS)
# ==================================================
if [[ "$TASK_STATUS" == "OK" ]]; then
  curl -s -X POST "$NTFY_URL/$NTFY_TOPIC" \
    -H "Title: Proxmox Backup Success" \
    -H "Priority: low" \
    -d "✅ Backup job completed successfully

🖥 Node:     $TASK_NODE
🕒 Started:  $START_TIME
🏁 Finished: $END_TIME
⏱ Duration: $DURATION_FMT"
elif [[ "$TASK_STATUS" == WARNINGS:* ]]; then
  # The job ran to the end; Proxmox flags a guest/step with a warning. Not a
  # failure, so do not page at high priority (a weekly "FAILED" for a warning
  # trains you to ignore the real ones).
  curl -s -X POST "$NTFY_URL/$NTFY_TOPIC" \
    -H "Title: Proxmox Backup finished with warnings" \
    -H "Priority: default" \
    -d "⚠️ Backup job completed with warnings

🖥 Node:     $TASK_NODE
🕒 Started:  $START_TIME
🏁 Finished: $END_TIME
⏱ Duration: $DURATION_FMT

Status: $TASK_STATUS
Check the Proxmox task log for which guest warned."
else
  curl -s -X POST "$NTFY_URL/$NTFY_TOPIC" \
    -H "Title: Proxmox Backup FAILED" \
    -H "Priority: high" \
    -d "❌ Backup job failed

🖥 Node:     $TASK_NODE
🕒 Started:  $START_TIME
🏁 Finished: $END_TIME
⏱ Duration: $DURATION_FMT

Status: $TASK_STATUS
Check the Proxmox task log for details."
fi
