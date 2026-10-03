#!/bin/bash
# Remove everything install-macos.sh created. Run as root.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }
rm -f /etc/ssh/sshd_config.d/60-hermes-diag.conf /etc/ssh/hermes-diag.authorized_keys
sshd -t
rm -rf /usr/local/lib/hermes-diag
dseditgroup -o edit -d hermes-diag -t user com.apple.access_ssh 2>/dev/null || true
dscl . -delete /Users/hermes-diag 2>/dev/null || true
echo "hermes-diag removed"
