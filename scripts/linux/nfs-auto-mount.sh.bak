#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Load environment (HOME, never repo)
# ==================================================
ENV_FILE="/home/ecloaiza/nfs-mount.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] Env file not found: $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# ==================================================
# Defaults (only if NOT defined in env)
# ==================================================
PING_COUNT="${PING_COUNT:-2}"
PING_TIMEOUT="${PING_TIMEOUT:-2}"

DEFAULT_NFS_OPTS="rw,hard,timeo=600,retrans=5,noatime"

# ==================================================
# Logging
# ==================================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [tars] $*"
}

# ==================================================
# Must be run as root
# ==================================================
if [[ "$EUID" -ne 0 ]]; then
  log "ERROR: This script must be run with sudo"
  exit 1
fi

# ==================================================
# Reachability check (USES ENV VALUES)
# ==================================================
is_reachable() {
  local ip="$1"
  ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$ip" >/dev/null 2>&1
}

# ==================================================
# Process one mount
# ==================================================
process_mount() {
  local NAS_IP="$1"
  local EXPORT="$2"
  local MOUNT_POINT="$3"
  local OPTIONS="$4"

  log "----------------------------------------"
  log "NAS:    $NAS_IP"
  log "Export: $EXPORT"
  log "Mount:  $MOUNT_POINT"

  [[ -d "$MOUNT_POINT" ]] || mkdir -p "$MOUNT_POINT"

  if mountpoint -q "$MOUNT_POINT"; then
    IS_MOUNTED=true
  else
    IS_MOUNTED=false
  fi

  if is_reachable "$NAS_IP"; then
    NAS_UP=true
    log "NAS reachable"
  else
    NAS_UP=false
    log "NAS NOT reachable"
  fi

  # Mount
  if [[ "$NAS_UP" == true && "$IS_MOUNTED" == false ]]; then
    log "Mounting"
    mount -t nfs -o "$OPTIONS" "$NAS_IP:$EXPORT" "$MOUNT_POINT"
    log "Mounted successfully"
    return
  fi

  # Unmount
  if [[ "$NAS_UP" == false && "$IS_MOUNTED" == true ]]; then
    log "Unmounting (NAS unreachable)"
    umount -f "$MOUNT_POINT"
    log "Unmounted successfully"
    return
  fi

  log "No action required"
}

# ==================================================
# Build mount list (ITERATIVE + BACKWARD COMPATIBLE)
# ==================================================

if [[ -n "${NFS_MOUNTS:-}" ]]; then
  # Extended multi-mount format (additive)
  while IFS='|' read -r NAS EXPORT MOUNT OPTS; do
    [[ -z "$NAS" || "$NAS" =~ ^# ]] && continue
    process_mount "$NAS" "$EXPORT" "$MOUNT" "${OPTS:-$DEFAULT_NFS_OPTS}"
  done <<< "$NFS_MOUNTS"
else
  # Original single-mount format (UNCHANGED)
  process_mount \
    "$NAS_HOST" \
    "$NFS_EXPORT" \
    "$MOUNT_POINT" \
    "$DEFAULT_NFS_OPTS"
fi

log "All mount checks complete"
