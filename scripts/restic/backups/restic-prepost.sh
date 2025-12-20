#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Cron-safe PATH
# ==================================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ==================================================
# Env files (HOME only)
# ==================================================
NFS_ENV="/home/ecloaiza/nfs-mount.env"
RESTIC_ENV="/home/ecloaiza/restic-backup.env"

# ==================================================
# Existing scripts (repo OK, env NOT ok)
# ==================================================
NFS_SCRIPT="/home/ecloaiza/scripts/linux/nfs-auto-mount.sh"

# ==================================================
# Logging
# ==================================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [restic-prepost] $*"
}

# ==================================================
# Must be root for mount/unmount
# ==================================================
if [[ "${EUID}" -ne 0 ]]; then
  log "ERROR: Must be run with sudo/root"
  exit 1
fi

# ==================================================
# Load envs
# ==================================================
if [[ ! -f "$NFS_ENV" ]]; then
  log "ERROR: Missing NFS env: $NFS_ENV"
  exit 1
fi

if [[ ! -f "$RESTIC_ENV" ]]; then
  log "ERROR: Missing restic env: $RESTIC_ENV"
  exit 1
fi

# shellcheck disable=SC1090
source "$NFS_ENV"
source "$RESTIC_ENV"

# ==================================================
# Validate expected vars from existing restic env format
# ==================================================
: "${NFS_SERVER:?Missing NFS_SERVER in $RESTIC_ENV}"
: "${NFS_EXPORT:?Missing NFS_EXPORT in $RESTIC_ENV}"
: "${MOUNT_POINT:?Missing MOUNT_POINT in $RESTIC_ENV}"
: "${SYMLINK_NAME:?Missing SYMLINK_NAME in $RESTIC_ENV}"

# Optional behavior flags (default conservative)
RESTIC_UNMOUNT_AFTER="${RESTIC_UNMOUNT_AFTER:-false}"

# ==================================================
# Require a restic command to run (no hardcoding)
# Usage:
#   sudo restic-prepost.sh restic backup /path ...
#   sudo restic-prepost.sh docker compose -f ... run --rm restic ...
# ==================================================
if [[ "$#" -lt 1 ]]; then
  log "ERROR: No command provided."
  log "Example:"
  log "  sudo $0 restic backup /home"
  exit 1
fi

if [[ ! -x "$NFS_SCRIPT" ]]; then
  log "ERROR: NFS mount script not executable: $NFS_SCRIPT"
  exit 1
fi

# ==================================================
# Pre-hook: ensure mounts are in desired state
# ==================================================
log "Pre-hook: ensuring NFS mounts"
"$NFS_SCRIPT"

# Verify the mountpoint your restic workflow expects is mounted
if ! mountpoint -q "$MOUNT_POINT"; then
  log "ERROR: Expected mount point is NOT mounted: $MOUNT_POINT"
  log "This usually means your restic env MOUNT_POINT and nfs-mount.env mount point(s) don't match."
  log "Fix by aligning MOUNT_POINT in /home/ecloaiza/restic-backup.env with the mount point(s) defined in /home/ecloaiza/nfs-mount.env."
  exit 1
fi

# ==================================================
# Run command
# ==================================================
log "Running: $*"
set +e
"$@"
RC=$?
set -e

# ==================================================
# Post-hook: optional unmount
# ==================================================
if [[ "$RESTIC_UNMOUNT_AFTER" == "true" ]]; then
  log "Post-hook: unmount requested (RESTIC_UNMOUNT_AFTER=true)"
  "$NFS_SCRIPT"
else
  log "Post-hook: unmount skipped (RESTIC_UNMOUNT_AFTER=false)"
fi

# ==================================================
# Final status
# ==================================================
if [[ "$RC" -eq 0 ]]; then
  log "Command completed successfully"
else
  log "Command FAILED with exit code $RC"
fi

exit "$RC"
