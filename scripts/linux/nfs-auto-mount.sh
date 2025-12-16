#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$HOME/nfs-mount.env"
LOG_FILE="/var/log/nfs-auto-mount.log"
HOSTNAME="$(hostname)"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$HOSTNAME] $*" | tee -a "$LOG_FILE"
}

# Load env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Env file not found: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

PING_COUNT="${PING_COUNT:-2}"
PING_TIMEOUT="${PING_TIMEOUT:-2}"

log "========================================"
log "NFS auto-mount run starting"
log "========================================"

# Safety: require NFS_MOUNTS
if [[ -z "${NFS_MOUNTS:-}" ]]; then
  log "ERROR: NFS_MOUNTS is not defined"
  exit 1
fi

# Iterate mounts
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  IFS='|' read -r NAS_IP NFS_EXPORT MOUNT_POINT MOUNT_OPTS <<< "$line"

  log "----------------------------------------"
  log "NAS:    $NAS_IP"
  log "Export: $NFS_EXPORT"
  log "Mount:  $MOUNT_POINT"
  log "Opts:   $MOUNT_OPTS"

  # Ensure mount directory exists
  mkdir -p "$MOUNT_POINT"

  # Check reachability PER NAS
  if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$NAS_IP" &>/dev/null; then
    log "NAS reachable"

    if mountpoint -q "$MOUNT_POINT"; then
      log "Already mounted → no action"
    else
      log "Mounting NFS share"
      mount -t nfs -o "$MOUNT_OPTS" "$NAS_IP:$NFS_EXPORT" "$MOUNT_POINT"
      log "Mount complete"
    fi

  else
    log "NAS NOT reachable"

    if mountpoint -q "$MOUNT_POINT"; then
      log "Stale NFS mount detected → unmounting"
      umount -f "$MOUNT_POINT" || umount -l "$MOUNT_POINT"
      log "Unmount complete"
    else
      log "Not mounted → no action"
    fi
  fi

done <<< "$NFS_MOUNTS"

log "========================================"
log "All mount checks complete"
