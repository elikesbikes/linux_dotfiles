#!/usr/bin/env bash
set -euo pipefail

#####################################
# SCRIPT LOCATION
#####################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#####################################
# LOAD HOST-SPECIFIC CONFIG (LOCAL)
#####################################
CONFIG_FILE="$SCRIPT_DIR/restic-backup.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

#####################################
# DEFAULTS (OVERRIDABLE PER HOST)
#####################################
NFS_SERVER="${NFS_SERVER:-192.168.5.51}"
NFS_EXPORT="${NFS_EXPORT:-/mnt/PROD1/nfs_restic/nfs_tars}"
MOUNT_POINT="${MOUNT_POINT:-/mnt/homenas/nfs_tars}"

SYMLINK_NAME="${SYMLINK_NAME:-backup}"
SYMLINK_TARGET="$MOUNT_POINT"

LOG_DIR="/var/log/restic"
LOG_FILE="$LOG_DIR/backup-$(date +%F).log"

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
# SETUP
#####################################
mkdir -p "$LOG_DIR"

# Ensure mount point exists
mkdir -p "$MOUNT_POINT"

# HARDENING: ensure mount point is a directory
if [[ ! -d "$MOUNT_POINT" ]]; then
  echo "ERROR: Mount point $MOUNT_POINT exists but is not a directory" | tee -a "$LOG_FILE"
  exit 1
fi

echo "==================================================" | tee -a "$LOG_FILE"
echo "Restic backup started at $(date)" | tee -a "$LOG_FILE"
echo "Using compose directory: $COMPOSE_DIR" | tee -a "$LOG_FILE"
echo "Mount point: $MOUNT_POINT" | tee -a "$LOG_FILE"

#####################################
# STEP 0: PING NFS SERVER
#####################################
echo "Pinging NFS server $NFS_SERVER..." | tee -a "$LOG_FILE"

if ! ping -c 2 -W 2 "$NFS_SERVER" >/dev/null 2>&1; then
  echo "ERROR: NFS server $NFS_SERVER unreachable. Aborting." | tee -a "$LOG_FILE"
  exit 1
fi

echo "NFS server reachable" | tee -a "$LOG_FILE"

###########
