#!/usr/bin/env bash
set -euo pipefail

#####################################
# CONSTANTS / DEFAULTS
#####################################
HOSTNAME="$(hostname -s)"
LOG_FILE="/var/log/nfs-auto-mount.log"

# Default env location (works even under sudo)
DEFAULT_ENV_FILE="/home/ecloaiza/nfs-mount.env"

#####################################
# LOGGING
#####################################
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$HOSTNAME] $*"
  echo "$msg"
  # Best-effort log append (avoid failing if /var/log perms/logrotate issues)
  { echo "$msg" >> "$LOG_FILE"; } 2>/dev/null || true
}

fail() {
  log "ERROR: $*"
  exit 1
}

#####################################
# ENV FILE RESOLUTION
#####################################
# Priority:
#  1) ENV_FILE_PATH (optional, if you export it or set it in sudoers env_keep)
#  2) /home/ecloaiza/nfs-mount.env
#  3) alongside the script (fallback)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE_PATH:-$DEFAULT_ENV_FILE}"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f "$SCRIPT_DIR/nfs-mount.env" ]]; then
    ENV_FILE="$SCRIPT_DIR/nfs-mount.env"
  fi
fi

if [[ ! -f "$ENV_FILE" ]]; then
  fail "Env file not found. Tried ENV_FILE_PATH, $DEFAULT_ENV_FILE, and $SCRIPT_DIR/nfs-mount.env"
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

#####################################
# VALIDATION
#####################################
: "${NFS_MOUNTS:?NFS_MOUNTS must be defined in the env file}"

PING_COUNT="${PING_COUNT:-2}"
PING_TIMEOUT="${PING_TIMEOUT:-2}"

#####################################
# HELPERS
#####################################
is_mounted_proc() {
  # Reliable even when NFS is stale/unreachable; does not traverse filesystem.
  local nas_ip="$1"
  local export_path="$2"
  local mount_point="$3"
  grep -qsE "^${nas_ip}:${export_path}[[:space:]]+${mount_point}[[:space:]]+nfs" /proc/self/mounts
}

#####################################
# START
#####################################
log "========================================"
log "NFS auto-mount run starting"
log "Using env: $ENV_FILE"
log "========================================"

#####################################
# PROCESS EACH MOUNT
#####################################
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  IFS='|' read -r NAS_IP NFS_EXPORT MOUNT_POINT MOUNT_OPTS <<< "$line"

  log "----------------------------------------"
  log "NAS:    $NAS_IP"
  log "Export: $NFS_EXPORT"
  log "Mount:  $MOUNT_POINT"
  log "Opts:   $MOUNT_OPTS"

  # IMPORTANT: Ping FIRST. Do not touch mount paths unless NAS is reachable.
  if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$NAS_IP" >/dev/null 2>&1; then
    log "NAS reachable"

    # Safe to touch filesystem paths now
    if [[ ! -d "$MOUNT_POINT" ]]; then
      log "Creating mount point"
      mkdir -p "$MOUNT_POINT"
    fi

    if is_mounted_proc "$NAS_IP" "$NFS_EXPORT" "$MOUNT_POINT"; then
      log "Already mounted → no action"
    else
      log "Mounting NFS"
      mount -t nfs -o "$MOUNT_OPTS" "$NAS_IP:$NFS_EXPORT" "$MOUNT_POINT"
      log "Mount complete"
    fi
  else
    log "NAS NOT reachable"

    # DO NOT touch the mount path here (can hang on hard/stale NFS).
    if is_mounted_proc "$NAS_IP" "$NFS_EXPORT" "$MOUNT_POINT"; then
      log "Stale NFS mount detected → unmounting"
      umount -fl "$MOUNT_POINT"
      log "Unmount complete"
    else
      log "No NFS mount present → no action"
    fi
  fi

done <<< "$NFS_MOUNTS"

log "========================================"
log "All mount checks complete"
