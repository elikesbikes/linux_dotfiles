#!/usr/bin/env bash
set -euo pipefail

#####################################
# nfs-auto-mount.sh
# Version: 1.1.2
#
# Status: FROZEN / PRODUCTION
#
# Description:
# Safely manages NFS mounts by mounting when the NFS transport
# is reachable and forcibly detaching stale mounts when it is not.
# Designed to be cron-safe and resilient against stale NFS hangs.
#
# Changelog (cumulative):
# - 1.1.0:
#   * Replaced ICMP ping with TCP/2049 health check
#   * Time-bounded forced lazy unmounts to prevent hangs
# - 1.1.1:
#   * Normalize mount points and exports to remove trailing slashes
#   * Fix false-negative mount detection for stubborn NFS mounts
# - 1.1.2:
#   * Canonicalize logging to /var/log/nfs-auto-mount.log
#   * Ensure consistent logging across cron, root, and manual runs
#####################################

#####################################
# CONSTANTS / DEFAULTS
#####################################
HOSTNAME="$(hostname -s)"

# Canonical log file (override allowed via LOG_FILE env)
DEFAULT_LOG_FILE="/var/log/nfs-auto-mount.log"
LOG_FILE="${LOG_FILE:-$DEFAULT_LOG_FILE}"

DEFAULT_ENV_FILE_1="/home/ecloaiza/.nfs-mount.env"   # preferred (hidden)
DEFAULT_ENV_FILE_2="/home/ecloaiza/nfs-mount.env"    # legacy

#####################################
# LOGGING
#####################################
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$HOSTNAME] $*"
  echo "$msg"

  # Best-effort append; never fail the script
  {
    touch "$LOG_FILE"
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${ENV_FILE_PATH:-$DEFAULT_ENV_FILE_1}"
[[ -f "$ENV_FILE" ]] || ENV_FILE="$DEFAULT_ENV_FILE_2"
[[ -f "$ENV_FILE" ]] || {
  [[ -f "$SCRIPT_DIR/nfs-mount.env" ]] && ENV_FILE="$SCRIPT_DIR/nfs-mount.env"
}

[[ -f "$ENV_FILE" ]] || fail "Env file not found"

# shellcheck disable=SC1090
source "$ENV_FILE"

#####################################
# VALIDATION
#####################################
: "${NFS_MOUNTS:?NFS_MOUNTS must be defined in the env file}"

NFS_PORT="${NFS_PORT:-2049}"
NFS_CONNECT_TIMEOUT_SECONDS="${NFS_CONNECT_TIMEOUT_SECONDS:-2}"
UMOUNT_TIMEOUT_SECONDS="${UMOUNT_TIMEOUT_SECONDS:-5}"

#####################################
# HELPERS
#####################################
normalize_path() {
  local p="$1"
  [[ "$p" != "/" ]] && p="${p%/}"
  echo "$p"
}

is_mounted_proc() {
  local nas_ip="$1"
  local export_path="$2"
  local mount_point="$3"

  grep -qsE "^${nas_ip}:${export_path}[[:space:]]+${mount_point}[[:space:]]+nfs" \
    /proc/self/mounts
}

nfs_transport_ok() {
  local nas_ip="$1"
  local port="$2"

  timeout "$NFS_CONNECT_TIMEOUT_SECONDS" \
    bash -c "</dev/tcp/${nas_ip}/${port}" \
    >/dev/null 2>&1
}

safe_umount_lazy_force() {
  local mount_point="$1"

  timeout "$UMOUNT_TIMEOUT_SECONDS" \
    umount -fl "$mount_point" \
    >/dev/null 2>&1
}

#####################################
# START
#####################################
log "========================================"
log "NFS auto-mount run starting"
log "Version: 1.1.2 (FROZEN)"
log "Log file: $LOG_FILE"
log "Using env: $ENV_FILE"
log "========================================"

#####################################
# PROCESS EACH MOUNT
#####################################
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  IFS='|' read -r NAS_IP NFS_EXPORT MOUNT_POINT MOUNT_OPTS <<< "$line"

  # Canonicalize paths
  NFS_EXPORT="$(normalize_path "$NFS_EXPORT")"
  MOUNT_POINT="$(normalize_path "$MOUNT_POINT")"

  log "----------------------------------------"
  log "NAS:    $NAS_IP"
  log "Export: $NFS_EXPORT"
  log "Mount:  $MOUNT_POINT"
  log "Opts:   $MOUNT_OPTS"

  if nfs_transport_ok "$NAS_IP" "$NFS_PORT"; then
    log "NFS transport reachable on TCP/$NFS_PORT"

    if [[ ! -d "$MOUNT_POINT" ]]; then
      log "Creating mount point"
      mkdir -p "$MOUNT_POINT"
    fi

    if is_mounted_proc "$NAS_IP" "$NFS_EXPORT" "$MOUNT_POINT"; then
      log "Already mounted → no action"
    else
      log "Mounting NFS"
      mount -t nfs -o "$MOUNT_OPTS" \
        "$NAS_IP:$NFS_EXPORT" "$MOUNT_POINT"
      log "Mount complete"
    fi
  else
    log "NFS transport NOT reachable on TCP/$NFS_PORT"

    if is_mounted_proc "$NAS_IP" "$NFS_EXPORT" "$MOUNT_POINT"; then
      log "Stale/blocked NFS mount detected → forcing lazy unmount"
      if safe_umount_lazy_force "$MOUNT_POINT"; then
        log "Unmount complete"
      else
        log "WARNING: umount timed out or failed"
      fi
    else
      log "No NFS mount present → no action"
    fi
  fi

done <<< "$NFS_MOUNTS"

log "========================================"
log "All mount checks complete"
