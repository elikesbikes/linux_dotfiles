#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Script: install_sudoers.sh
# Version: 1.0.0
#
# Versioning:
# 1.0.0 - Initial implementation:
#         - Deploys sudoers drop-in files to /etc/sudoers.d via the
#           existing `syncs` alias target (sudoers/sync-sudoers.sh).
#         - State-based idempotency via XDG state marker.
#         - Locates the sync script from the alias path, falling back to
#           the in-repo copy; validates prerequisites (unison) first.
#
# Note: This deploys *configuration* (sudoers files) rather than a package,
#       but it lives in core because it is foundational and the user drives
#       it via the `syncs` alias. The actual sync logic is owned by
#       sync-sudoers.sh; this wrapper only handles discovery + idempotency.
# ==================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.sh}.log"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"
STATE_FILE="$STATE_DIR/sudoers"

mkdir -p "$LOG_DIR"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "[$SCRIPT_NAME] Version: $SCRIPT_VERSION"
echo "[$SCRIPT_NAME] Starting at: $(date)"
echo "Log: $LOG_FILE"
echo "=================================================="

# --------------------------------------------------
# State-based idempotency check (authoritative)
# --------------------------------------------------
if [[ -f "$STATE_FILE" ]]; then
  echo "STATE: sudoers already marked as deployed ($STATE_FILE)"
  echo "Re-run by removing the marker above, or run \`syncs\` directly."
  echo "Nothing to do. Exiting."
  exit 0
fi

# --------------------------------------------------
# Locate the sync script
#   1. The `syncs` alias target ($HOME/scripts/linux/sudoers/sync-sudoers.sh)
#   2. The in-repo copy, derived from this script's location
#      (.../linux_dotfiles/scripts/linux/sudoers/sync-sudoers.sh)
# --------------------------------------------------
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SYNC_CANDIDATES=(
  "$HOME/scripts/linux/sudoers/sync-sudoers.sh"
  "$REPO_ROOT/scripts/linux/sudoers/sync-sudoers.sh"
)

SYNC_SCRIPT=""
for candidate in "${SYNC_CANDIDATES[@]}"; do
  if [[ -f "$candidate" ]]; then
    SYNC_SCRIPT="$candidate"
    break
  fi
done

if [[ -z "$SYNC_SCRIPT" ]]; then
  echo "FAIL: could not find sync-sudoers.sh. Looked in:"
  printf '  - %s\n' "${SYNC_CANDIDATES[@]}"
  exit 1
fi
echo "Using sync script: $SYNC_SCRIPT"

# --------------------------------------------------
# Prerequisite check
#   sync-sudoers.sh relies on unison + a ~/.unison/sudoers.prf profile.
# --------------------------------------------------
if ! command -v unison >/dev/null 2>&1; then
  echo "FAIL: unison not found. Run cli/install_unison.sh first."
  exit 1
fi

if [[ ! -f "$HOME/.unison/sudoers.prf" ]]; then
  echo "FAIL: missing Unison profile $HOME/.unison/sudoers.prf"
  echo "Deploy dotfiles (which provide the profile) before syncing sudoers."
  exit 1
fi

# --------------------------------------------------
# Deploy sudoers (the `syncs` alias)
# --------------------------------------------------
echo "Deploying sudoers via sync-sudoers.sh ..."
bash "$SYNC_SCRIPT"

# --------------------------------------------------
# Post-deploy validation
# --------------------------------------------------
if sudo visudo -c >/dev/null 2>&1; then
  echo "SUCCESS: sudoers deployed and /etc/sudoers validates clean."
  touch "$STATE_FILE"
else
  echo "FAIL: sudoers validation failed after sync."
  exit 1
fi

echo "=================================================="
echo "[$SCRIPT_NAME] Completed at: $(date)"
echo "=================================================="
