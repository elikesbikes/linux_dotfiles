#!/usr/bin/env bash
set -euo pipefail

#####################################
# LOAD HOST-SPECIFIC CONFIG (OPTIONAL)
#####################################
CONFIG_FILE="/etc/restic-backup.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

#####################################
# DEFAULTS (CAN BE OVERRIDDEN)
#####################################
NFS_SERVER="${NFS_SERVER:-192.168.5.51}"
NFS_EXPORT="${NFS_EXPORT:-/mnt/PROD1/nfs_restic/nfs_tars}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/homenas/nfs_tars}"

LOG_DIR="/var/log/restic"
LOG_FILE="$LOG_DIR/backup-$(date +%F).log"

#####################################
# AUTO-DETECT docker-compose.yml
#####################################
COMPOSE_CANDIDATES=(
  "/home/ecloaiza/DevOps/docker/restic/docker-compose.yml"
  "/home/ecloaiza/devops/docker/restic/docker-compose.yml"
  "/home/ecloaiza/docker/restic/docker-compose.yml"
)

COMPOSE_FILE=""
for candidate in "${COMPOSE_CANDIDATES[@]}"; do
  if [[ -f "$candidate" ]]; then
    COMPOSE_FILE="$candidate"
    break
  fi
done

if [[ -z "$COMPOSE_FILE" ]]; then
  echo "ERROR: docker-compose.yml not found in known locations" >&2
  exit 1
fi

#####################################
# SETUP
#####################################
mkdir -p "$LOG_DIR"
mkdir -p "$MOUNT_POINT"

echo "=== Restic backup started at $(date) ===" | tee -a "$LOG_FILE"
echo "Using compose file: $COMPOSE_FILE" | tee -a "$LOG_FILE"

#####################################
# STEP 0: PING NFS SERVER
#####################################
echo "Pinging NFS server $NFS_SERVER..." | tee -a "$LOG_FILE"

if ! ping -c 2 -W 2 "$NFS_SERVER" >/dev/null 2>&1; then
  echo "ERROR: NFS server $NFS_SERVER unreachable. Aborting." | tee -a "$LOG_FILE"
  exit 1
fi

echo "NFS server reachable" | tee -a "$LOG_FILE"

#####################################
# STEP 1: ENSURE NFS MOUNT
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
# STEP 2: RUN RESTIC BACKUP
#####################################
docker compose \
  -f "$COMPOSE_FILE" \
  run --rm restic backup \
  /data/docker-volumes \
  >> "$LOG_FILE" 2>&1

echo "=== Restic backup completed at $(date) ===" | tee -a "$LOG_FILE"
