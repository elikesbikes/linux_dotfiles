#!/usr/bin/env bash
set -euo pipefail

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

if [[ -z "$COMPOSE_DIR" ]]; then
  echo "ERROR: docker-compose.yml not found in known locations" >&2
  exit 1
fi

#####################################
# LOAD HOST CONFIG FROM COMPOSE DIR
#####################################
CONFIG_FILE="$COMPOSE_DIR/restic-backup.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  echo "ERROR: restic-backup.env not found in $COMPOSE_DIR" >&2
  exit 1
fi

#####################################
# REQUIRED VARIABLES
#####################################
: "${NFS_SERVER:?NFS_SERVER not set}"
: "${NFS_EXPORT:?NFS_EXPORT not set}"
: "${MOUNT_POINT:?MOUNT_POINT not set}"

#####################################
# LOGGING
#####################################
LOG_DIR="/var/log/restic"
LOG_FILE="$LOG_DIR/backup-$(date +%F).log"
mkdir -p "$LOG_DIR"

echo "==================================================" | tee -a "$LOG_FILE"
echo "Restic backup started at $(date)" | tee -a "$LOG_FILE"
echo "Compose dir: $COMPOSE_DIR" | tee -a "$LOG_FILE"
echo "Mount point: $MOUNT_POINT" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

#####################################
# STEP 0: ENSURE MOUNT POINT EXISTS
#####################################
mkdir -p "$MOUNT_POINT"

if [[ ! -d "$MOUNT_POINT" ]]; then
  echo "ERROR: Mount point exists but is not a directory" | tee -a "$LOG_FILE"
  exit 1
fi

#####################################
# STEP 1: PING NFS SERVER
#####################################
if ! ping -c 2 -W 2 "$NFS_SERVER" >/dev/null 2>&1; then
  echo "ERROR: NFS server unreachable" | tee -a "$LOG_FILE"
  exit 1
fi

#####################################
# STEP 2: ENSURE NFS IS MOUNTED
#####################################
if ! mountpoint -q "$MOUNT_POINT"; then
  echo "Mounting NFS..." | tee -a "$LOG_FILE"
  mount "$NFS_SERVER:$NFS_EXPORT" "$MOUNT_POINT" >>"$LOG_FILE" 2>&1
fi

if ! mountpoint -q "$MOUNT_POINT"; then
  echo "ERROR: NFS mount failed" | tee -a "$LOG_FILE"
  exit 1
fi

#####################################
# STEP 3: ENSURE RESTIC REPO EXISTS
#####################################
echo "Checking restic repository..." | tee -a "$LOG_FILE"

(
  cd "$COMPOSE_DIR"

  if docker compose run --rm restic snapshots >/dev/null 2>&1; then
    echo "Restic repository exists" | tee -a "$LOG_FILE"
  else
    echo "Restic repository missing, initializing..." | tee -a "$LOG_FILE"
    docker compose run --rm restic init >>"$LOG_FILE" 2>&1
    echo "Restic repository initialized" | tee -a "$LOG_FILE"
  fi
)

#####################################
# STEP 4: RUN BACKUP
#####################################
(
  cd "$COMPOSE_DIR"
  docker compose run --rm restic backup /data/docker-volumes
) >>"$LOG_FILE" 2>&1

echo "Restic backup completed at $(date)" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
