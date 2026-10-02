#!/usr/bin/env bash
# Install the read-only `hermes-diag` SSH account on THIS host (run as root: sudo ./install.sh <pubkey-file>).
#
# Creates, all root-owned so the account cannot change its own restrictions:
#   user              hermes-diag  (no password, no docker/sudo group, shell only used to start the forced command)
#   /usr/local/lib/hermes-diag/diag.py                 the gate (copied from this directory)
#   /etc/ssh/hermes-diag.authorized_keys               the ONE allowed key, pinned to a source address
#   /etc/ssh/sshd_config.d/60-hermes-diag.conf         Match User hermes-diag: forced command, no tty/forwarding
#   /etc/sudoers.d/60-hermes-diag                      EXACT commands only (docker logs / journalctl), no wildcards
# Everything is validated BEFORE it is activated; uninstall.sh removes it all.
#
# Usage: sudo ./install.sh /path/to/hermes-diag.pub [allowed-source-ip]    (default source: 192.168.5.46 = endurance)
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "must run as root: sudo $0 <pubkey-file> [source-ip]" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBFILE="${1:?usage: $0 <pubkey-file> [source-ip]}"
SRC_IP="${2:-192.168.5.46}"
ACCOUNT=hermes-diag
LIB=/usr/local/lib/hermes-diag
AUTH=/etc/ssh/hermes-diag.authorized_keys
SSHD_DROPIN=/etc/ssh/sshd_config.d/60-hermes-diag.conf
SUDOERS=/etc/sudoers.d/60-hermes-diag

say() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---- 1. validate inputs (nothing has been changed yet) -------------------------------------------
say "Validating inputs"
[[ -f "$HERE/diag.py" ]] || die "diag.py not found next to this script"
[[ -f "$PUBFILE" ]] || die "public key file not found: $PUBFILE"
[[ $(grep -c . "$PUBFILE") -eq 1 ]] || die "the key file must contain exactly ONE key"
KEYLINE="$(cat "$PUBFILE")"
[[ "$KEYLINE" == ssh-ed25519\ * ]] || die "only ssh-ed25519 keys are accepted"
[[ "$KEYLINE" != *\"* && "$KEYLINE" != *$'\n'* ]] || die "key line contains characters that could inject options"
ssh-keygen -lf "$PUBFILE" >/dev/null || die "not a valid public key"
[[ "$SRC_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "source must be a single IPv4 address"
python3 -m py_compile "$HERE/diag.py"
command -v sudo >/dev/null && command -v visudo >/dev/null || die "sudo/visudo missing"
echo "key: $(ssh-keygen -lf "$PUBFILE")  allowed only from: $SRC_IP"

# ---- 2. build the sudoers rules from the allowlists in diag.py (single source of truth) ----------
say "Building sudoers rules from diag.py"
mapfile -t CONTAINERS < <(python3 -c "import sys; sys.path.insert(0,'$HERE'); import diag; print('\n'.join(diag.CONTAINERS))")
mapfile -t UNITS < <(python3 -c "import sys; sys.path.insert(0,'$HERE'); import diag; print('\n'.join(diag.UNITS))")
DOCKER="$(python3 -c "import sys; sys.path.insert(0,'$HERE'); import diag; print(diag.DOCKER)")"
JOURNALCTL="$(python3 -c "import sys; sys.path.insert(0,'$HERE'); import diag; print(diag.JOURNALCTL)")"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
{
  echo "# Managed by scripts/hermes-diag/install.sh - EXACT commands only (no wildcards). Host-local; not synced."
  echo "Cmnd_Alias HERMES_DIAG = \\"
  rules=()
  for c in "${CONTAINERS[@]}"; do [[ "$c" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "bad container name $c"; rules+=("$DOCKER logs --tail 200 $c"); done
  for u in "${UNITS[@]}";      do [[ "$u" =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]] || die "bad unit name $u";      rules+=("$JOURNALCTL -u $u -n 200 --no-pager -o short-iso"); done
  for i in "${!rules[@]}"; do
    sep=","; [[ $i -eq $((${#rules[@]}-1)) ]] && sep=""
    echo "    ${rules[$i]}$sep \\"
  done | sed '$ s/ \\$//'
  echo "Defaults:$ACCOUNT !requiretty, logfile=/var/log/sudo-hermes-diag.log"
  echo "$ACCOUNT ALL=(root) NOPASSWD: HERMES_DIAG"
} > "$TMP"
visudo -cf "$TMP" >/dev/null || { cat "$TMP"; die "generated sudoers failed validation"; }
echo "sudoers OK ($((${#CONTAINERS[@]} + ${#UNITS[@]})) exact commands)"

# ---- 3. apply ----------------------------------------------------------------------------------
say "Creating account $ACCOUNT"
if id "$ACCOUNT" &>/dev/null; then
  echo "already exists"
else
  # '*' = no valid password but NOT locked, so key auth still works under UsePAM.
  useradd --create-home --shell /bin/sh --comment "Hermes read-only diagnostics" --password '*' "$ACCOUNT"
fi
for g in docker sudo adm systemd-journal root; do
  if id -nG "$ACCOUNT" | tr ' ' '\n' | grep -qx "$g"; then die "$ACCOUNT must not be in group $g"; fi
done

say "Installing the gate (root-owned)"
install -d -m 0755 -o root -g root "$LIB"
install -m 0755 -o root -g root "$HERE/diag.py" "$LIB/diag.py"

say "Installing the authorized key (root-owned, pinned to $SRC_IP)"
printf 'from="%s",restrict,command="%s/diag.py" %s\n' "$SRC_IP" "$LIB" "$KEYLINE" > "$AUTH"
chown root:root "$AUTH"; chmod 0644 "$AUTH"

say "Installing sudoers (validated)"
install -m 0440 -o root -g root "$TMP" "$SUDOERS"
visudo -c >/dev/null

say "Installing sshd restrictions"
cat > "$SSHD_DROPIN" <<EOF
# Managed by scripts/hermes-diag/install.sh
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
EOF
chmod 0644 "$SSHD_DROPIN"
if ! sshd -t; then rm -f "$SSHD_DROPIN"; die "sshd rejected the config; the drop-in was removed again"; fi

say "Verifying the EFFECTIVE sshd settings for $ACCOUNT from $SRC_IP"
EFF="$(sshd -T -C "user=$ACCOUNT,host=$SRC_IP,addr=$SRC_IP" 2>&1)"
echo "$EFF" | grep -E '^(forcecommand|authorizedkeysfile|permittty|allowtcpforwarding|allowagentforwarding|x11forwarding|passwordauthentication|authenticationmethods|permituserrc) ' || true
grep -q "^forcecommand $LIB/diag.py" <<<"$EFF" || { rm -f "$SSHD_DROPIN"; die "ForceCommand is not in effect; drop-in removed, sshd NOT reloaded"; }
grep -q "^permittty no" <<<"$EFF" || { rm -f "$SSHD_DROPIN"; die "PermitTTY is not 'no'; drop-in removed"; }

say "Reloading sshd (existing sessions are kept)"
systemctl reload ssh 2>/dev/null || systemctl reload sshd

say "Self-test of the gate as $ACCOUNT"
sudo -u "$ACCOUNT" env SSH_ORIGINAL_COMMAND="status" SSH_CLIENT="127.0.0.1 1 22" "$LIB/diag.py" | head -3 || true
sudo -u "$ACCOUNT" env SSH_ORIGINAL_COMMAND="cat /etc/shadow" SSH_CLIENT="127.0.0.1 1 22" "$LIB/diag.py" || true
sudo -u "$ACCOUNT" -- sudo -n -l 2>&1 | sed -n '/may run/,$p' | head -8

echo
echo "DONE. Remove with: sudo $HERE/uninstall.sh"
