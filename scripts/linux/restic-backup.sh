#!/usr/bin/env bash
set -euo pipefail

#####################################
# SCRIPT LOCATION
#####################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  echo "ERROR: restic-backup.env not found next to docker-compose.yml in $COMPOSE_DIR" >&2
  exit 1
fi

#####################################
# REQUIRED VARIABLES (FAIL FAST)
#####################################
: "${NFS_SERVER:?NFS_SERVER not set in restic-backup.env}"
: "${NFS_EXPORT:?NFS_EXPORT not set in restic-backup.env}"
: "${MOUNT_POINT:?MOUNT_POINT not set in restic-backup.env}"

SYMLINK_NAME="${SYMLINK_NAME:-backup}"
SYMLINK_TARGET="$MOUNT_POINT"

#####################################
# LOGGING
#####################################
LOG_DIR="/var/log/restic"
LOG_FILE="$LOG_DIR/backup-$(date +%F).log"

mkdir -p "$LOG_DIR"

echo "==================================================" | tee -a "$LOG_FILE"
echo "Restic backup started at $(date)" | tee -a "$LOG_FILE"
echo "Compose directory: $COMPOSE_DIR" | tee -a "$LOG_FILE"
echo "Config file: $CONFIG_FILE" | tee -a "$LOG_FILE"
echo "NFS server: $NFS_SERVER" | tee -a "$LOG_FILE"
echo "NFS export: $NFS_EXPORT" | tee -a "$LOG_FILE"
echo "Mount point: $MOUNT_POINT" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

#####################################
# STEP 0: ENSURE MOUNT POINT EXISTS
#####################################
mkdir -p "$MOUNT_POINT"

# HARDENING: must be a directory
if [[ ! -d "$MOUNT_POINT" ]]; then
  echo "ERROR: Mount point $MOUNT_POINT exists but is not a directory" | tee -a "$LOG_FILE"
  exit 1
fi

#####################################
# STEP 1: PING NFS SERVER
#####################################
echo "Pinging NFS server $NFS_SERVER..." | tee -a "$LOG_FILE"

if ! ping -c 2 -W 2 "$NFS_SERVER" >/dev/null 2>&1; then
  echo "ERROR: NFS server $NFS_SERVER unreachable. Aborting." | tee -a "$LOG_FILE"
  exit 1
fi

echo "NFS server reachable" | tee -a "$LOG_FILE"

#####################################
# STEP 2: ENSURE NFS MOUNT
#####################################
if mountpoint -q "$MOUNT_POINT"; then
  echo "NFS already mounted at $MOUNT_POINT" | tee -a "$LOG_FILE"
else
  echo "NFS not mounted, attempting mount..." | tee -a "$LOG_FILE"

  mount "$NFS_SERVER:$NFS_EXPORT" "$MOUNT_POINT" >> "$LOG_FILE" 2>&1

  if ! mountpoint -q "$MOUNT_POINT"; then
    echo "ERROR: Failed to mount NFS at $MOUNT_POINT" | tee -a "$LOG_FILE"
    exit 1
  fi

  echo "NFS mounted successfully at $MOUNT_POINT" | tee -a "$LOG_FILE"
fi

#####################################
# STEP 3: ENSURE BACKUP SYMLINK
#####################################
SYMLINK_PATH="$SCRIPT_DIR/$SYMLINK_NAME"

if [[ -L "$SYMLINK_PATH" ]]; then
  CURRENT_TARGET="$(readlink -f "$SYMLINK_PATH")"

  if [[ "$CURRENT_TARGET" != "$SYMLINK_TARGET" ]]; then
    echo "ERROR: Symlink $SYMLINK_PATH points to $CURRENT_TARGET, expected $SYMLINK_TARGET" | tee -a "$LOG_FILE"
    exit 1
  fi

  echo "Backup symlink exists and is correct" | tee -a "$LOG_FILE"

elif [[ -e "$SYMLINK_PATH" ]]; then
  echo "ERROR: $SYMLINK_PATH exists but is not a symlink" | tee -a "$LOG_FILE"
  exit 1

else
  echo "Backup symlink missing, creating it..." | tee -a "$LOG_FILE"
  ln -s "$SYMLINK_TARGET" "$SYMLINK_PATH"
  echo "Backup symlink created: $SYMLINK_PATH → $SYMLINK_TARGET" | tee -a "$LOG_FILE"
fi

#####################################
# STEP 4: RUN RESTIC BACKUP
#####################################
(
  cd "$COMPOSE_DIR"
  docker compose run --rm restic backup /data/docker-volumes
) >> "$LOG_FILE" 2>&1

echo "Restic backup completed at $(date)" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
