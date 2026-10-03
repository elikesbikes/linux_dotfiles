#!/bin/bash
# Install the read-only `hermes-diag` SSH account on a macOS host (run as an admin: sudo ./install-macos.sh <pubkey-file> [source-ip]).
# macOS counterpart of install.sh. Differences that matter:
#   * no useradd/systemctl: the account is a hidden standard user made with dscl, sshd is launchd on-demand (no reload needed);
#   * macOS restricts SSH to members of the group com.apple.access_ssh (here: the nested `admin` group), enforced by PAM
#     (pam_sacl). The new account is added to that group DIRECTLY; this does not widen access for anyone else;
#   * no sudoers: only the generic no-privilege commands exist on macOS (see GENERIC in diag.py).
# Everything is validated before it is activated; uninstall-macos.sh removes it all. Python 3.9 (system) is enough.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

[[ $EUID -eq 0 ]] || { echo "must run as root: sudo $0 <pubkey-file> [source-ip]" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || { echo "this installer is for macOS; use install.sh on Linux" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBFILE="${1:?usage: $0 <pubkey-file> [source-ip]}"
SRC_IP="${2:-192.168.5.46}"
ACCOUNT=hermes-diag
ACL_GROUP=com.apple.access_ssh
LIB=/usr/local/lib/hermes-diag
AUTH=/etc/ssh/hermes-diag.authorized_keys
DROPIN=/etc/ssh/sshd_config.d/60-hermes-diag.conf

say() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

say "Validating inputs"
[[ -f "$HERE/diag.py" ]] || die "diag.py not found next to this script"
[[ -f "$PUBFILE" ]] || die "public key file not found: $PUBFILE"
[[ $(grep -c . "$PUBFILE") -eq 1 ]] || die "the key file must contain exactly ONE key"
KEYLINE="$(cat "$PUBFILE")"
[[ "$KEYLINE" == ssh-ed25519\ * ]] || die "only ssh-ed25519 keys are accepted"
[[ "$KEYLINE" != *\"* ]] || die "key line contains characters that could inject options"
ssh-keygen -lf "$PUBFILE" >/dev/null || die "not a valid public key"
[[ "$SRC_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "source must be a single IPv4 address"
/usr/bin/python3 -m py_compile "$HERE/diag.py"
grep -q '^Include /etc/ssh/sshd_config.d/' /etc/ssh/sshd_config || die "sshd_config does not Include sshd_config.d/*"
echo "key: $(ssh-keygen -lf "$PUBFILE")  allowed only from: $SRC_IP"

say "Recording the effective sshd settings of OTHER users (to prove the drop-in does not leak)"
OTHERS=("${SUDO_USER:-root}" nobody someone-else)
declare -a BEFORE
for i in "${!OTHERS[@]}"; do
  BEFORE[$i]="$(sshd -T -C "user=${OTHERS[$i]},host=$SRC_IP,addr=$SRC_IP" 2>&1 | sort | shasum | cut -c1-16)"
  echo "  ${OTHERS[$i]}: ${BEFORE[$i]}"
done

say "Creating hidden standard user $ACCOUNT"
if dscl . -read "/Users/$ACCOUNT" UniqueID &>/dev/null; then
  echo "already exists"
else
  UID_NEW=590
  dscl . -list /Users UniqueID | awk '{print $2}' | grep -qx "$UID_NEW" && die "uid $UID_NEW already used"
  dscl . -create "/Users/$ACCOUNT"
  dscl . -create "/Users/$ACCOUNT" UserShell /bin/sh
  dscl . -create "/Users/$ACCOUNT" RealName "Hermes read-only diagnostics"
  dscl . -create "/Users/$ACCOUNT" UniqueID "$UID_NEW"
  dscl . -create "/Users/$ACCOUNT" PrimaryGroupID 20
  dscl . -create "/Users/$ACCOUNT" NFSHomeDirectory /var/empty
  dscl . -create "/Users/$ACCOUNT" IsHidden 1
  dscl . -create "/Users/$ACCOUNT" Password '*'
fi
if dseditgroup -o checkmember -m "$ACCOUNT" admin &>/dev/null; then die "$ACCOUNT must not be in group admin"; fi

say "Allowing $ACCOUNT through macOS's SSH ACL ($ACL_GROUP)"
dseditgroup -o edit -a "$ACCOUNT" -t user "$ACL_GROUP"
dseditgroup -o checkmember -m "$ACCOUNT" "$ACL_GROUP"

say "Installing the gate (root-owned)"
install -d -m 0755 -o root -g wheel /usr/local/lib "$LIB"
install -m 0755 -o root -g wheel "$HERE/diag.py" "$LIB/diag.py"

say "Installing the authorized key (root-owned, pinned to $SRC_IP)"
printf 'from="%s",restrict,command="%s/diag.py" %s\n' "$SRC_IP" "$LIB" "$KEYLINE" > "$AUTH"
chown root:wheel "$AUTH"; chmod 0644 "$AUTH"

say "Installing sshd restrictions"
cat > "$DROPIN" <<EOT
# Managed by scripts/hermes-diag/install-macos.sh
Match User $ACCOUNT
    AuthorizedKeysFile $AUTH
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    ForceCommand $LIB/diag.py
    PermitTTY no
    AllowTcpForwarding no
    AllowStreamLocalForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTunnel no
    PermitUserRC no
    GatewayPorts no
    MaxSessions 2
EOT
chown root:wheel "$DROPIN"; chmod 0644 "$DROPIN"
if ! sshd -t; then rm -f "$DROPIN"; die "sshd rejected the config; the drop-in was removed again"; fi

say "Verifying that other users' effective sshd settings are UNCHANGED"
for i in "${!OTHERS[@]}"; do
  after="$(sshd -T -C "user=${OTHERS[$i]},host=$SRC_IP,addr=$SRC_IP" 2>&1 | sort | shasum | cut -c1-16)"
  [[ "$after" == "${BEFORE[$i]}" ]] || { rm -f "$DROPIN"; die "sshd settings for '${OTHERS[$i]}' changed: the Match block leaked. Drop-in removed."; }
  echo "  ${OTHERS[$i]}: unchanged"
done

say "Verifying the EFFECTIVE sshd settings for $ACCOUNT from $SRC_IP"
EFF="$(sshd -T -C "user=$ACCOUNT,host=$SRC_IP,addr=$SRC_IP" 2>&1)"
echo "$EFF" | grep -i -E '^(forcecommand|authorizedkeysfile|permittty|allowtcpforwarding|allowagentforwarding|passwordauthentication|authenticationmethods) ' || true
grep -qi "^forcecommand $LIB/diag.py" <<<"$EFF" || { rm -f "$DROPIN"; die "ForceCommand is not in effect; drop-in removed"; }
grep -qi "^permittty no" <<<"$EFF" || { rm -f "$DROPIN"; die "PermitTTY is not 'no'; drop-in removed"; }
echo "(sshd on macOS is started on demand by launchd, so there is nothing to reload)"

say "Self-test of the gate as $ACCOUNT"
sudo -u "$ACCOUNT" env SSH_ORIGINAL_COMMAND="os" SSH_CLIENT="127.0.0.1 1 22" "$LIB/diag.py" || true
sudo -u "$ACCOUNT" env SSH_ORIGINAL_COMMAND="cat /etc/shadow" SSH_CLIENT="127.0.0.1 1 22" "$LIB/diag.py" || true
echo; echo "DONE. Remove with: sudo $HERE/uninstall-macos.sh"
