#!/usr/bin/env bash
set -Eeuo pipefail

#####################################
# CONFIG
#####################################
ENV_FILE="/home/ecloaiza/nfs-mount.env"
LOG_PREFIX="[nfs-unmount]"

#####################################
# HELPERS
#####################################
log() {
  echo "$(date '+%F %T') $LOG_PREFIX $*"
}

#####################################
# VALIDATION
#####################################
if [[ ! -f "$ENV_FILE" ]]; then
  log "ERROR: Env file not found: $ENV_FILE"
  exit 1
fi

#####################################
# LOAD ENV
#####################################
# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ -z "${NFS_MOUNTS:-}" ]]; then
  log "ERROR: NFS_MOUNTS is empty or undefined"
  exit 1
fi

#####################################
# UNMOUNT LOOP
#####################################
log "Starting NFS unmount sequence"

echo "$NFS_MOUNTS" | while IFS="|" read -r server export mountpoint options; do
  # Skip empty / malformed lines
  [[ -z "${mountpoint:-}" ]] && continue

  if mountpoint -q "$mountpoint" 2>/dev/null; then
    log "Force-unmounting $mountpoint (from $server:$export)"
    if umount -fl "$mountpoint" 2>/dev/null; then
      log "Successfully detached $mountpoint"
    else
      log "WARNING: Failed to unmount $mountpoint (continuing)"
    fi
  else
    log "Not mounted: $mountpoint"
  fi
done

#####################################
# OPTIONAL: NFS CLIENT RESET (SAFE)
#####################################
log "Restarting nfs-client.target to clear stale handles"
systemctl restart nfs-client.target 2>/dev/null || true

log "NFS unmount sequence completed"
exit 0
