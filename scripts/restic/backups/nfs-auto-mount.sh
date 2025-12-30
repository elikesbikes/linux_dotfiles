#!/usr/bin/env bash
set -euo pipefail

#####################################
# nfs-auto-mount.sh
# Version: 1.1.0
#
# Changelog (cumulative)
# - 1.1.0: Fix stale-mount cleanup by using TCP/2049 health check (not ICMP ping),
#          and time-bounding umount to prevent hangs under pathological NFS states.
#####################################

#####################################
# CONSTANTS / DEFAULTS
#####################################
HOSTNAME="$(hostname -s)"

# Prefer a user-writable log by default (cron-safe without sudo).
DEFAULT_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nfs-auto-mount"
DEFAULT_LOG_FILE="$DEFAULT_LOG_DIR/nfs-auto-mount.log"
LOG_FILE="${LOG_FILE:-$DEFAULT_LOG_FILE}"

# Default env locations (works even under sudo)
# Priority order handled below.
DEFAULT_ENV_FILE_1="/home/ecloaiza/.nfs-mount.env"  # preferred (hidden)
DEFAULT_ENV_FILE_2="/home/ecloaiza/nfs-mount.env"   # legacy (non-hidden)

#####################################
# LOGGING
#####################################
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$HOSTNAME] $*"
  echo "$msg"

  # Best-effort log append (avoid failing if perms/issues)
  {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$msg" >> "$LOG_FILE"
  } 2>/dev/null || true
}

fail() {
  log "ERROR: $*"
  exit 1
}

#####################################
# ENV FILE RESOLUTION
#####################################
# Priority:
#  1) ENV_FILE_PATH (optional, if exported or set in sudoers env_keep)
#  2) /home/ecloaiza/.nfs-mount.env (preferred hidden)
#  3) /home/ecloaiza/nfs-mount.env  (legacy)
#  4) alongside the script (fallback)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${ENV_FILE_PATH:-$DEFAULT_ENV_FILE_1}"
if [[ ! -f "$ENV_FILE" ]]; then
  ENV_FILE="$DEFAULT_ENV_FILE_2"
fi
if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f "$SCRIPT_DIR/nfs-mount.env" ]]; then
    ENV_FILE="$SCRIPT_DIR/nfs-mount.env"
  fi
fi

if [[ ! -f "$ENV_FILE" ]]; then
  fail "Env file not found. Tried ENV_FILE_PATH, $DEFAULT_ENV_FILE_1, $DEFAULT_ENV_FILE_2, and $SCRIPT_DIR/nfs-mount.env"
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

#####################################
# VALIDATION
#####################################
: "${NFS_MOUNTS:?NFS_MOUNTS must be defined in the env file}"

# Keep ping knobs for optional diagnostics / legacy, but we no longer rely on ICMP for health.
PING_COUNT="${PING_COUNT:-2}"
PING_TIMEOUT="${PING_TIMEOUT:-2}"

# NFS transport health check knobs
NFS_PORT="${NFS_PORT:-2049}"
NFS_CONNECT_TIMEOUT_SECONDS="${NFS_CONNECT_TIMEOUT_SECONDS:-2}"

# Unmount safety knobs
UMOUNT_TIMEOUT_SECONDS="${UMOUNT_TIMEOUT_SECONDS:-5}"

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

nfs_transport_ok() {
  # IMPORTANT: Do not touch filesystem paths here.
  # We check the actual NFS port (default 2049) with a hard timeout.
  local nas_ip="$1"
  local port="$2"
  timeout "$NFS_CONNECT_TIMEOUT_SECONDS" bash -c "</dev/tcp/${nas_ip}/${port}" >/dev/null 2>&1
}

safe_umount_lazy_force() {
  local mount_point="$1"

  # DO NOT stat/ls/df the mount point. Just attempt detach with a hard timeout.
  if timeout "$UMOUNT_TIMEOUT_SECONDS" umount -fl "$mount_point" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

#####################################
# START
#####################################
log "========================================"
log "NFS auto-mount run starting"
log "Version: 1.1.0"
log "Using env: $ENV_FILE"
log "Log file: $LOG_FILE"
log "Health check: TCP/${NFS_PORT} timeout=${NFS_CONNECT_TIMEOUT_SECONDS}s"
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

  # IMPORTANT: NFS PORT CHECK FIRST. Do not touch mount paths unless NFS transport is healthy.
  if nfs_transport_ok "$NAS_IP" "$NFS_PORT"; then
    log "NFS transport reachable on TCP/${NFS_PORT}"

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
    log "NFS transport NOT reachable on TCP/${NFS_PORT}"

    # DO NOT touch the mount path here (can hang on hard/stale NFS).
    if is_mounted_proc "$NAS_IP" "$NFS_EXPORT" "$MOUNT_POINT"; then
      log "Stale/blocked NFS mount detected → forcing lazy unmount (time-bounded)"
      if safe_umount_lazy_force "$MOUNT_POINT"; then
        log "Unmount complete"
      else
        log "WARNING: umount timed out or failed (kernel may be wedged). Manual intervention may be required."
      fi
    else
      log "No NFS mount present → no action"
    fi
  fi

done <<< "$NFS_MOUNTS"

log "========================================"
log "All mount checks complete"
