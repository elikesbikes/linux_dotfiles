#!/usr/bin/env bash
# Install (or refresh) the Proton Pass SSH agent watchdog as a user timer. Idempotent. Linux/systemd only (not macOS).
# Usage: ~/scripts/proton-pass/install-ssh-agent-watchdog.sh
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/systemd"
DST="$HOME/.config/systemd/user"
command -v systemctl >/dev/null || { echo "no systemd here: skipping" >&2; exit 0; }
mkdir -p "$DST"
for u in proton-pass-ssh-agent-watchdog.service proton-pass-ssh-agent-watchdog.timer; do
  ln -sfn "$SRC/$u" "$DST/$u"
done
systemctl --user daemon-reload
systemctl --user enable --now proton-pass-ssh-agent-watchdog.timer
systemctl --user list-timers proton-pass-ssh-agent-watchdog.timer --no-pager | head -2
