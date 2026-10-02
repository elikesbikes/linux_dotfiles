#!/usr/bin/env bash
# Remove everything install.sh created. Safe to re-run. Usage: sudo ./uninstall.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "must run as root: sudo $0" >&2; exit 1; }
rm -f /etc/sudoers.d/60-hermes-diag /etc/ssh/sshd_config.d/60-hermes-diag.conf /etc/ssh/hermes-diag.authorized_keys
rm -rf /usr/local/lib/hermes-diag
sshd -t && { systemctl reload ssh 2>/dev/null || systemctl reload sshd; }
if id hermes-diag &>/dev/null; then pkill -u hermes-diag || true; userdel -r hermes-diag 2>/dev/null || userdel hermes-diag; fi
visudo -c >/dev/null
echo "hermes-diag removed (sudo log /var/log/sudo-hermes-diag.log kept for audit)."
