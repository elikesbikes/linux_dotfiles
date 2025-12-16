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
# LOAD CONSOLIDATED ENV
#####################################
ENV_FILE="/home/ecloaiza/restic.env"
[[ -f "$ENV_FILE" ]] || fail "Missing env file: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

#####################################
# REQUIRED VARIABLES
#####################################
: "${RESTIC_REPOSITORY:?Missing RESTIC_REPOSITORY}"
: "${RESTIC_PASSWORD:?Missing RESTIC_PASSWORD}"
: "${NFS_SERVER:?Missing NFS_SERVER}"
: "${NFS_EXPORT:?Missing NFS_EXPORT}"
: "${MOUNT_POINT:?Missing MOUNT_POINT}"
: "${PING_COUNT:?Missing PING_COUNT}"
: "${PING_TIMEOUT:?Missing PING_TIMEOUT}"

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

COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

#####################################
# LOGGING
#####################################
LOG_DIR="/var/log/restic"
LOG_FILE="$LOG_DIR/backup-$(date +%F).log"
mkdir -p "$LOG_DIR"

{
  echo "=================================================="
  echo "Restic backup started at $(date)"
  echo "Host: $HOSTNAME"
  echo "Compose file: $COMPOSE_FILE"
  echo "Env file: $ENV_FILE"
  echo "=================================================="
} | tee -a "$LOG_FILE"

#####################################
# PRE-HOOK: ENSURE NFS MOUNT
#####################################
NFS_SCRIPT="/home/ecloaiza/scripts/linux/nfs-auto-mount.sh"
[[ -x "$NFS_SCRIPT" ]] || fail "nfs-auto-mount.sh not executable"

ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$NFS_SERVER" >/dev/null 2>&1 \
  || fail "NFS server unreachable"

"$NFS_SCRIPT" >>"$LOG_FILE" 2>&1 || fail "nfs-auto-mount.sh failed"
mountpoint -q "$MOUNT_POINT" || fail "NFS not mounted"

#####################################
# BUILD BACKUP PATHS (CONTAINER VIEW)
#####################################
BACKUP_PATHS=("/data/docker-volumes")

CANDIDATE_BIND_PATHS=(
  "/data/bind-volumes/docker"
  "/data/bind-volumes/devops/docker"
  "/data/bind-volumes/Devops/docker"
  "/data/bind-volumes/DevOps/docker"
)

echo "Detecting bind-mount paths (container view)..." | tee -a "$LOG_FILE"

for path in "${CANDIDATE_BIND_PATHS[@]}"; do
  if docker compose -f "$COMPOSE_FILE" run --rm --entrypoint sh restic \
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
if docker compose -f "$COMPOSE_FILE" run --rm restic snapshots >/dev/null 2>&1; then
  echo "Restic repository exists" | tee -a "$LOG_FILE"
else
  docker compose -f "$COMPOSE_FILE" run --rm restic init >>"$LOG_FILE" 2>&1 \
    || fail "Failed to initialize restic repository"
fi

#####################################
# RUN BACKUP
#####################################
echo "Running restic backup for:" | tee -a "$LOG_FILE"
for p in "${BACKUP_PATHS[@]}"; do
  echo "  - $p" | tee -a "$LOG_FILE"
done

docker compose -f "$COMPOSE_FILE" run --rm restic backup "${BACKUP_PATHS[@]}" \
  >>"$LOG_FILE" 2>&1 || fail "Restic backup failed"

#####################################
# POST-HOOK
#####################################
if [[ "${RESTIC_POST_CHECK:-true}" == "true" ]]; then
  "$NFS_SCRIPT" >>"$LOG_FILE" 2>&1 || true
fi

#####################################
# SUCCESS
#####################################
notify "✅ [$HOSTNAME] Restic backup completed successfully"
echo "==================================================" | tee -a "$LOG_FILE"
