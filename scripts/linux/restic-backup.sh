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
  "/home/ecloaiza/Devops/docker/restic"
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
# LOAD HOST CONFIG (NFS)
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
echo "==================================================" | tee -a "$LOG_FILE"

#####################################
# ENSURE NFS MOUNT (HOST SIDE)
#####################################
mkdir -p "$MOUNT_POINT"

ping -c 2 -W 2 "$NFS_SERVER" >/dev/null 2>&1 || fail "NFS server unreachable"

if ! mountpoint -q "$MOUNT_POINT"; then
  mount "$NFS_SERVER:$NFS_EXPORT" "$MOUNT_POINT" >>"$LOG_FILE" 2>&1
fi

mountpoint -q "$MOUNT_POINT" || fail "NFS mount failed"

#####################################
# BUILD BACKUP PATHS (CONTAINER VIEW)
#####################################
BACKUP_PATHS=()

# Always include docker named volumes
BACKUP_PATHS+=("/data/docker-volumes")

# Candidate bind-mount docker roots (container paths)
CANDIDATE_BIND_PATHS=(
  "/data/bind-volumes/docker"
  "/data/bind-volumes/devops/docker"
  "/data/bind-volumes/Devops/docker"
  "/data/bind-volumes/DevOps/docker"
)

echo "Detecting bind-mount paths (container view)..." | tee -a "$LOG_FILE"

for path in "${CANDIDATE_BIND_PATHS[@]}"; do
  if docker compose run --rm --entrypoint sh restic -c "[ -d '$path' ]" >/dev/null 2>&1; then
    BACKUP_PATHS+=("$path")
    echo "✔ Including $path" | tee -a "$LOG_FILE"
  else
    echo "✘ Skipping $path (not present in container)" | tee -a "$LOG_FILE"
  fi
done

#####################################
# ENSURE RESTIC REPOSITORY EXISTS
#####################################
cd "$COMPOSE_DIR"

if docker compose run --rm restic snapshots >/dev/null 2>&1; then
  echo "Restic repository exists" | tee -a "$LOG_FILE"
else
  docker compose run --rm restic init >>"$LOG_FILE" 2>&1 \
    || fail "Failed to initialize restic repository"
fi

#####################################
# RUN BACKUP
#####################################
echo "Running restic backup for:" | tee -a "$LOG_FILE"
for p in "${BACKUP_PATHS[@]}"; do
  echo "  - $p" | tee -a "$LOG_FILE"
done

docker compose run --rm restic backup "${BACKUP_PATHS[@]}" >>"$LOG_FILE" 2>&1 \
  || fail "Restic backup failed"

#####################################
# SUCCESS
#####################################
notify "✅ [$HOSTNAME] Restic backup completed successfully"
echo "==================================================" | tee -a "$LOG_FILE"
