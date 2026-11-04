#!/bin/bash
# xcode-cleanup.sh — remove Xcode leftovers that fill a macOS build host's disk.
#
# Why: parallel testing (`xcodebuild test`, Xcode's Test action) clones a
# simulator per worker into ~/Library/Developer/XCTestDevices and often leaves
# the clones behind. On kipp they reached 159 folders and, with old
# DerivedData, filled the disk on 2026-11-03 (Syncthing stopped at <1% free).
#
# What it removes:
#   1. every parallel-testing clone (`simctl --set testing`), plus orphan
#      clone folders simctl no longer knows about
#   2. DerivedData folders with nothing modified in the last $KEEP_DAYS days
#
# Safety: skips entirely while any xcodebuild runs or any testing clone is
# booted, so it never pulls a simulator out from under a test. Simulators
# made with `simctl create` (CI jobs) live in the default set and are not
# touched.
#
# Installed on kipp as ~/.local/bin/xcode-cleanup.sh, run daily by the
# LaunchAgent com.elikesbikes.xcode-cleanup (see the .plist next to this file).
# Logs to syslog (tag xcode-cleanup) and stdout.

set -u

TAG="xcode-cleanup"
KEEP_DAYS="${KEEP_DAYS:-7}"
DEV="$HOME/Library/Developer"
CLONES="$DEV/XCTestDevices"
DERIVED="$DEV/Xcode/DerivedData"

log() {
  logger -t "$TAG" "$*"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

free_gb() {
  df -k "$HOME" | awk 'NR==2 { printf "%.1f", $4 / 1048576 }'
}

if pgrep -x xcodebuild >/dev/null; then
  log "skip: xcodebuild is running"
  exit 0
fi

if xcrun simctl --set testing list devices 2>/dev/null | grep -q "(Booted)"; then
  log "skip: a parallel-testing clone is booted"
  exit 0
fi

before=$(free_gb)

# 1. Parallel-testing clones.
clone_count=0
if [[ -d $CLONES ]]; then
  xcrun simctl --set testing delete all >/dev/null 2>&1 || log "warn: simctl --set testing delete all failed"
  clone_count=$(find "$CLONES" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  find "$CLONES" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
fi

# 2. DerivedData untouched for KEEP_DAYS days.
derived_removed=0
if [[ -d $DERIVED ]]; then
  for dir in "$DERIVED"/*/; do
    [[ -d $dir ]] || continue
    if [[ -z $(find "$dir" -maxdepth 3 -mtime "-$KEEP_DAYS" -print -quit 2>/dev/null) ]]; then
      rm -rf "$dir"
      derived_removed=$((derived_removed + 1))
    fi
  done
fi

after=$(free_gb)
log "done: orphan clone dirs removed=$clone_count, DerivedData removed=$derived_removed (older than ${KEEP_DAYS}d), free ${before} GB -> ${after} GB"
