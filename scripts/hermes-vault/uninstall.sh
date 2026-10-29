#!/usr/bin/env bash
# Remove everything install.sh created (run as root: sudo ./uninstall.sh). The vault notes Hermes created stay.
# Also revoke the PAT itself afterwards:  pass-cli personal-access-token delete --name hailmary-hermes-vault
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }
rm -f /etc/ssh/sshd_config.d/61-hermes-vault.conf /etc/ssh/hermes-vault.authorized_keys
sshd -t && { systemctl reload ssh 2>/dev/null || systemctl reload sshd; }
rm -f /etc/sudoers.d/60-hermes-vault; visudo -c >/dev/null
if tpm2_getcap handles-persistent | grep -qi 0x81010002; then tpm2_evictcontrol -Q -C o -c 0x81010002; fi
rm -rf /usr/local/lib/hermes-vault
id hermes-vault &>/dev/null && userdel -r hermes-vault 2>/dev/null
echo "removed. NOTE: sudoers/sudoers.d/60-hermes-vault in linux_dotfiles must be deleted too, or the pipeline puts the rule back (harmless without the account)."
