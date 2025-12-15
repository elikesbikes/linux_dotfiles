#!/usr/bin/env bash
set -euo pipefail

#####################################
# CONSTANTS
#####################################
ENV_FILE="/home/ecloaiza/nfs-mount.env"
HOSTNAME="$(hostname -s)"

#####################################
# LOAD CONFIG
#####################################
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Env file not found: $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

#####################################
# VALIDATION
#####################################
: "${NAS_HOST:?Missing NAS_HOST}"
: "${NFS_EXPORT:?Missing NFS_EXPORT}"
: "${MOUNT_POINT:?Missing MOUNT_POINT}"
: "${PING_COUNT:?Missing PING_COUNT}"
: "${PING_TIMEOUT:?Missing PING_TIMEOUT}"

#####################################
# LOGGING
#####################################
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$HOSTNAME] $*"
}

#####################################
# ENSURE MOUNT POINT EXISTS
#####################################
if [[ ! -d "$MOUNT_POINT" ]]; then
  log "Creating mount point: $MOUNT_POINT"
  mkdir -p "$MOUNT_POINT"
fi

#####################################
# CHECK NAS REACHABILITY
#####################################
if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$NAS_HOST" >/dev/null 2>&1; then
  NAS_UP=true
else
  NAS_UP=false
fi

#####################################
# MOUNT / UNMOUNT LOGIC
#####################################
if $NAS_UP; then
  log "NAS reachable ($NAS_HOST)"

  if mountpoint -q "$MOUNT_POINT"; then
    log "NFS already mounted at $MOUNT_POINT"
  else
    log "Mounting NFS share"
    mount "$NAS_HOST:$NFS_EXPORT" "$MOUNT_POINT"
    log "NFS mounted successfully"
  fi
else
  log "NAS NOT reachable ($NAS_HOST)"

  if mountpoint -q "$MOUNT_POINT"; then
    log "Unmounting NFS share"
    umount "$MOUNT_POINT"
    log "NFS unmounted successfully"
  else
    log "NFS already unmounted"
  fi
fi
