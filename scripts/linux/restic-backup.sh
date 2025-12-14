#!/usr/bin/env bash
set -euo pipefail

#####################################
# NTFY CONFIG
#####################################
NTFY_SERVER="https://ntfy.home.elikesbikes.com"
NTFY_TOPIC="backups"
HOSTNAME="$(hostname -s)"

notify() {
  local msg="$1"
  curl -fsS -X POST "$NTFY_SERVER/$NTFY_TOPIC" \
    -H "Title: Restic Backup ($HOSTNAME)" \
    -H "Priority: 3" \
    -d "$msg" >/dev/null || true
}

fail() {
  local msg="$1"
  echo "ERROR: $msg"
  notify "❌ [$HOSTNAME] $msg"
  exit 1
}

#####################################
# AUTO-DETECT COMPOSE DIRECTORY
#####################################
COMPOSE_DIRS=(
  "/home/ecloaiza/DevOps/docker/restic"
  "/home/ecloaiza/devops/docker/restic"
  "/home/ecloaiza/docker/restic"
)

COMPOSE_DIR=""
for dir in "${COMPOSE_DIRS[@]}"; do
  if [[ -f "$dir/docker-compose.yml" ]]; then
    COMPOSE_DIR="$dir"
    break
  fi
done

[[ -z "$COMPOSE_DIR" ]] && fail "docker-compose.yml not found in expected locations"

#####################################
# LOAD HOST CONFIG FROM COMPOSE DIR
#####################################
CONFIG_FILE="$COMPOSE_DIR/restic-backup.env"
[[ -f "$CONFIG_FILE" ]] || fail "restic-backup.env not found in $COMPOSE_DIR"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

#####################################
# REQUIRED VARIABLES
#####################################
: "${NFS_SERVER:?Missing NFS_SERVER}"
: "${NFS_EXPORT:?Missing NFS_EXPORT}"
: "${MOUNT_POINT:?Missing MOUNT_POINT}"

#####################################
# LOGGING
#####################################
LOG_DIR="/var/log/restic"
LOG_FILE="$LOG_DIR/backup-$(date +%F).log"
mkdir -p "$LOG_DIR"

echo "==================================================" | tee -a "$LOG_FILE"
echo "Restic backup started at $(date)" | tee -a "$LOG_FILE"
echo "Host: $HOSTNAME" | tee -a "$LOG_FILE"
echo "Compose dir: $COMPOSE_DIR" | tee -a "$LOG_FILE"
echo "Mount point: $MOUNT_POINT" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

#####################################
# STEP 0: ENSURE MOUNT POINT EXISTS
#####################################
mkdir -p "$MOUNT_POINT"
[[ -d "$MOUNT_POINT" ]] || fail "Mount point exists but is not a directory"

#####################################
# STEP 1: PING NFS SERVER
#####################################
ping -c 2 -W 2 "$NFS_SERVER" >/dev/null 2>&1 || fail "NFS server $NFS_SERVER unreachable"

#####################################
# STEP 2: ENSURE NFS IS MOUNTED
#####################################
if ! mountpoint -q "$MOUNT_POINT"; then
  echo "Mounting NFS..." | tee -a "$LOG_FILE"
  mount "$NFS_SERVER:$NFS_EXPORT" "$MOUNT_POINT" >>"$LOG_FILE" 2>&1
fi

mountpoint -q "$MOUNT_POINT" || fail "NFS mount failed"

#####################################
# STEP 3: BUILD BACKUP PATH LIST (SMART & RESTRICTED)
#####################################
BACKUP_PATHS=()

# Always back up docker volumes
BACKUP_PATHS+=("/var/lib/docker/volumes")

# Only standardized bind-mount roots
CANDIDATE_PATHS=(
  "/home/ecloaiza/docker"
  "/home/ecloaiza/Devops/docker"
  "/home/ecloaiza/devops/docker"
)

echo "Detecting bind-mount paths..." | tee -a "$LOG_FILE"

for path in "${CANDIDATE_PATHS[@]}"; do
  if [[ -d "$path" ]]; then
    BACKUP_PATHS+=("$path")
    echo "✔ Including $path" | tee -a "$LOG_FILE"
  else
    echo "✘ Skipping $path (not present)" | tee -a "$LOG_FILE"
  fi
done

[[ "${#BACKUP_PATHS[@]}" -gt 1 ]] || fail "No bind-mount paths found to back up"

#####################################
# STEP 4: ENSURE RESTIC REPOSITORY EXISTS
#####################################
cd "$COMPOSE_DIR"

if docker compose run --rm restic snapshots >/dev/null 2>&1; then
  echo "Restic repository exists" | tee -a "$LOG_FILE"
else
  echo "Restic repository missing, initializing..." | tee -a "$LOG_FILE"
  docker compose run --rm restic init >>"$LOG_FILE" 2>&1 \
    || fail "Failed to initialize restic repository"
  echo "Restic repository initialized" | tee -a "$LOG_FILE"
fi

#####################################
# STEP 5: RUN BACKUP
#####################################
echo "Running restic backup for paths:" | tee -a "$LOG_FILE"
for p in "${BACKUP_PATHS[@]}"; do
  echo "  - $p" | tee -a "$LOG_FILE"
done

docker compose run --rm restic backup "${BACKUP_PATHS[@]}" >>"$LOG_FILE" 2>&1 \
  || fail "Restic backup command failed"

#####################################
# SUCCESS
#####################################
echo "Restic backup completed successfully at $(date)" | tee -a "$LOG_FILE"
notify "✅ [$HOSTNAME] Restic backup completed successfully"

echo "==================================================" | tee -a "$LOG_FILE"
