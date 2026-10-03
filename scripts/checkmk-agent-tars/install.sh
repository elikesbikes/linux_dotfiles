#!/usr/bin/env bash
# Install the CheckMK agent on tars (Arch, no deb) in legacy pull mode, like rocky: unpack the official 2.4.0p27 package and run its own
# POSIX setup scripts. Run as root:  sudo ./install.sh   (expects data.tar.gz and the local checks next to this script)
# Then the CheckMK server pulls port 6556 (no registration, no credentials). The agent only answers connections from hailmary (see step 4).
set -uo pipefail   # no -e on purpose: the package's own scripts (e.g. migrate.sh) return 1 when there is nothing to do, as dpkg's postinst tolerates
[[ $EUID -eq 0 ]] || { echo "must run as root: sudo $0" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$HERE/data.tar.gz" ]] || { echo "data.tar.gz (from check-mk-agent_2.4.0p27-1_all.deb) not found next to this script" >&2; exit 1; }
say() { printf '\n==> %s\n' "$*"; }
run() { "$@"; rc=$?; [ $rc -eq 0 ] || echo "   (exit $rc: $*)"; return 0; }

say "1. Unpacking the agent package (files only; pacman does not track them)"
tar -xzf "$HERE/data.tar.gz" -C / || { echo 'unpack failed' >&2; exit 1; }
say "2. Running the package's own setup scripts (as its postinst does)"
run sh /var/lib/cmk-agent/scripts/migrate.sh
run sh /var/lib/cmk-agent/scripts/super-server/setup cleanup
run env BIN_DIR=/usr/bin sh /var/lib/cmk-agent/scripts/super-server/setup deploy
run env BIN_DIR=/usr/bin sh /var/lib/cmk-agent/scripts/manage-agent-user.sh
run sh /var/lib/cmk-agent/scripts/super-server/setup trigger
run sh /var/lib/cmk-agent/scripts/manage-binaries.sh install
say "3. Legacy pull mode (like rocky): no registration needed"
run cmk-agent-ctl delete-all --enable-insecure-connections
say "4. Local checks for tars"
install -d -m 0755 /etc/check_mk /usr/lib/check_mk_agent/local
install -m 0644 "$HERE/docker-expected.tars.conf" /etc/check_mk/docker-expected.conf
install -m 0755 "$HERE/docker_containers" "$HERE/gpu_nvidia" /usr/lib/check_mk_agent/local/
say "5. Self-test (agent output, local section)"
check_mk_agent 2>/dev/null | sed -n '/<<<local/,/<<</p' | head -20
say "6. Listening on 6556?"
ss -ltn | grep ':6556' || echo "NOT listening on 6556 - check: systemctl status cmk-agent-ctl-daemon"
echo; echo "DONE. If tars has a firewall, allow 192.168.5.25 -> tcp/6556."
