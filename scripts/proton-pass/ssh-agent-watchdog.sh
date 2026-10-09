#!/usr/bin/env bash
# Restart proton-pass-ssh-agent when it has lost its Proton session.
#
# Why: pass-cli's ssh-agent keeps running after its session dies (logs "Error fetching events: No active session" every 30 s)
# and keeps serving the keys it already has, so systemd's Restart=on-failure never fires and Proton changes stop arriving.
# Found 2026-10-09: every host had been in that state for ~24 h. Run by proton-pass-ssh-agent-watchdog.timer.
#
# Each restart is a PAT login, and all hosts share one public IP (Proton rate-limits logins, 429/2028), so: act only on
# the CURRENT agent process's errors, and restart at most once per PP_WATCHDOG_MIN_GAP_S (default 30 min) per host.
set -euo pipefail

UNIT=proton-pass-ssh-agent.service
TAG=proton-pass-watchdog
MIN_GAP="${PP_WATCHDOG_MIN_GAP_S:-1800}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/proton-pass"
STAMP="$STATE/ssh-agent-watchdog.last-restart"
mkdir -p "$STATE"

# A stopped or failed agent is systemd's job (Restart=on-failure), not ours.
systemctl --user is-active --quiet "$UNIT" || exit 0
pid="$(systemctl --user show -p MainPID --value "$UNIT")"
[ -n "$pid" ] && [ "$pid" != 0 ] || exit 0

errors="$(journalctl --user _PID="$pid" --since "-3min" --no-pager -o cat 2>/dev/null | grep -c 'No active session' || true)"
[ "${errors:-0}" -ge 3 ] || exit 0

now="$(date +%s)"; last="$(cat "$STAMP" 2>/dev/null || echo 0)"
if (( now - last < MIN_GAP )); then
  logger -p user.notice -t "$TAG" "agent has no Proton session ($errors errors in 3 min) but was restarted $((now - last))s ago; waiting"
  exit 0
fi

echo "$now" > "$STAMP"
logger -p user.warning -t "$TAG" "agent has no Proton session ($errors errors in 3 min); restarting $UNIT"
systemctl --user restart "$UNIT"
