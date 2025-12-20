#!/usr/bin/env bash
set -euo pipefail

#####################################
# CONSTANTS / PATHS
#####################################
SCRIPT_DIR="/home/ecloaiza/scripts/restic/backups"
NFS_MOUNT_SCRIPT="$SCRIPT_DIR/nfs-auto-mount.sh"
ENV_FILE="/home/ecloaiza/restic.env"

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
# VALIDATE DEPENDENCIES
#####################################
[[ -x "$NFS_MOUNT_SCRIPT" ]] || fail "Missing nfs-auto-mount.sh at $NFS_MOUNT_SCRIPT"
[[ -f "$ENV_FILE" ]] || fail "Missing env file $ENV_FILE"

#####################################
# LOAD ENV (single source of truth)
#####################################
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${RESTIC_REPOSITORY:?Missing RESTIC_REPOSITORY}"
: "${RESTIC_PASSWORD:?Missing RESTIC_PASSWORD}"

#####################################
# LOGGING
#####################################
LOG_DIR="/var/log/restic"
LOG_FILE="$LOG_DIR/backup-$(date +%F).log"
mkdir -p "$LOG_DIR"

echo "==================================================" | tee -a "$LOG_FILE"
echo "Restic backup started at $(date)" | tee -a "$LOG_FILE"
echo "Host: $HOSTNAME" | tee -a "$LOG_FILE"
echo "Script dir: $SCRIPT_DIR" | tee -a "$LOG_FILE"
echo "Env file: $ENV_FILE" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

#####################################
# PRE-HOOK: ENSURE NFS MOUNT
#####################################
"$NFS_MOUNT_SCRIPT" >>"$LOG_FILE" 2>&1 \
  || fail "NFS mount pre-hook failed"

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

[[ -z "$COMPOSE_DIR" ]] && fail "docker-compose.yml not found"

#####################################
# BUILD BACKUP PATHS (CONTAINER VIEW)
#####################################
BACKUP_PATHS=(
  "/data/docker-volumes"
)

CANDIDATE_BIND_PATHS=(
  "/data/bind-volumes/docker"
  "/data/bind-volumes/devops/docker"
  "/data/bind-volumes/Devops/docker"
  "/data/bind-volumes/DevOps/docker"
)

echo "Detecting bind-mount paths (container view)..." | tee -a "$LOG_FILE"

for path in "${CANDIDATE_BIND_PATHS[@]}"; do
  if docker compose -f "$COMPOSE_DIR/docker-compose.yml" \
       run --rm --entrypoint sh restic \
       -c "[ -d '$path' ]" >/dev/null 2>&1; then
    BACKUP_PATHS+=("$path")
    echo "✔ Including $path" | tee -a "$LOG_FILE"
  else
    echo "✘ Skipping $path (not present in container)" | tee -a "$LOG_FILE"
  fi
done

#####################################
# ENSURE RESTIC REPO EXISTS
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

docker compose run --rm restic backup "${BACKUP_PATHS[@]}" \
  >>"$LOG_FILE" 2>&1 || fail "Restic backup failed"

#####################################
# POST-HOOK: OPTIONAL UNMOUNT
#####################################
if [[ "${RESTIC_UNMOUNT_AFTER:-false}" == "true" ]]; then
  echo "Unmounting NFS after backup" | tee -a "$LOG_FILE"
  umount /mnt/homenas/nfs_tars >>"$LOG_FILE" 2>&1 || true
fi

#####################################
# SUCCESS
#####################################
notify "✅ [$HOSTNAME] Restic backup completed successfully"
echo "==================================================" | tee -a "$LOG_FILE"
