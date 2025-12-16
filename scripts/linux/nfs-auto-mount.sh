#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/home/ecloaiza/nfs-mount.env"
HOSTNAME="$(hostname -s)"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$HOSTNAME] $*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

# Load env
if [[ ! -f "$ENV_FILE" ]]; then
  fail "Env file not found: $ENV_FILE"
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${NAS_HOST:?}"
: "${NFS_EXPORT:?}"
: "${MOUNT_POINT:?}"
: "${PING_COUNT:=2}"
: "${PING_TIMEOUT:=2}"

log "----------------------------------------"
log "NAS:    $NAS_HOST"
log "Export: $NFS_EXPORT"
log "Mount:  $MOUNT_POINT"

# Check reachability FIRST — nothing else is safe before this
if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$NAS_HOST" >/dev/null 2>&1; then
  log "NAS reachable"

  # Safe to touch filesystem now
  if [[ ! -d "$MOUNT_POINT" ]]; then
    log "Creating mount point"
    mkdir -p "$MOUNT_POINT"
  fi

  if grep -qsE "^$NAS_HOST:$NFS_EXPORT[[:space:]]+$MOUNT_POINT[[:space:]]+nfs" /proc/self/mounts; then
    log "Already mounted"
  else
    log "Mounting NFS"
    mount "$NAS_HOST:$NFS_EXPORT" "$MOUNT_POINT"
    log "Mount successful"
  fi
else
  log "NAS NOT reachable"

  # DO NOT TOUCH THE PATH — kernel may block
  if grep -qsE "^$NAS_HOST:$NFS_EXPORT[[:space:]]+$MOUNT_POINT[[:space:]]+nfs" /proc/self/mounts; then
    log "Stale NFS mount detected → unmounting"
    umount -fl "$MOUNT_POINT"
    log "Unmount complete"
  else
    log "No NFS mount present"
  fi
fi

log "All mount checks complete"
