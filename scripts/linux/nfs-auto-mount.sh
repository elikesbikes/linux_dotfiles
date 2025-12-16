#!/usr/bin/env bash
set -euo pipefail

#####################################
# CONSTANTS
#####################################
ENV_FILE="/home/ecloaiza/nfs-mount.env"
HOSTNAME="$(hostname -s)"

#####################################
# LOGGING
#####################################
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$HOSTNAME] $*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

#####################################
# LOAD CONFIG
#####################################
if [[ ! -f "$ENV_FILE" ]]; then
  fail "Env file not found: $ENV_FILE"
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

#####################################
# VALIDATION
#####################################
: "${NFS_MOUNTS:?NFS_MOUNTS must be defined}"
: "${PING_COUNT:=2}"
: "${PING_TIMEOUT:=2}"

#####################################
# START
#####################################
log "========================================"
log "NFS auto-mount run starting"
log "========================================"

#####################################
# CHECK NAS REACHABILITY (ONCE)
#####################################
NAS_REACHABLE=false
PRIMARY_NAS="$(echo "$NFS_MOUNTS" | head -n1 | cut -d'|' -f1)"

if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$PRIMARY_NAS" >/dev/null 2>&1; then
  NAS_REACHABLE=true
  log "NAS reachable: $PRIMARY_NAS"
else
  log "NAS NOT reachable: $PRIMARY_NAS"
fi

#####################################
# PROCESS EACH MOUNT
#####################################
while IFS= read -r line; do
  # Skip empty lines
  [[ -z "$line" ]] && continue

  IFS='|' read -r NAS_HOST NFS_EXPORT MOUNT_POINT MOUNT_OPTS <<< "$line"

  log "----------------------------------------"
  log "NAS:    $NAS_HOST"
  log "Export: $NFS_EXPORT"
  log "Mount:  $MOUNT_POINT"
  log "Opts:   $MOUNT_OPTS"

  #####################################
  # NAS UP → MOUNT
  #####################################
  if [[ "$NAS_REACHABLE" == true ]]; then
    # Safe to touch filesystem paths ONLY here
    if [[ ! -d "$MOUNT_POINT" ]]; then
      log "Creating mount point"
      mkdir -p "$MOUNT_POINT"
    fi

    if grep -qsE "^$NAS_HOST:$NFS_EXPORT[[:space:]]+$MOUNT_POINT[[:space:]]+nfs" /proc/self/mounts; then
      log "Already mounted"
    else
      log "Mounting NFS"
      mount -o "$MOUNT_OPTS" "$NAS_HOST:$NFS_EXPORT" "$MOUNT_POINT"
      log "Mount successful"
    fi

  #####################################
  # NAS DOWN → UNMOUNT
  #####################################
  else
    # DO NOT TOUCH FILESYSTEM PATHS
    if grep -qsE "^$NAS_HOST:$NFS_EXPORT[[:space:]]+$MOUNT_POINT[[:space:]]+nfs" /proc/self/mounts; then
      log "Stale NFS mount detected → unmounting"
      umount -fl "$MOUNT_POINT"
      log "Unmount complete"
    else
      log "No NFS mount present"
    fi
  fi

done <<< "$NFS_MOUNTS"

log "========================================"
log "All mount checks complete"
