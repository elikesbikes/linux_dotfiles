#!/usr/bin/env bash
# Install the read-only `hermes-diag` SSH account on THIS host (run as root: sudo ./install.sh <pubkey-file>).
#
# Creates, all root-owned so the account cannot change its own restrictions:
#   user              hermes-diag  (no password, no docker/sudo group, shell only used to start the forced command)
#   /usr/local/lib/hermes-diag/diag.py                 the gate (copied from this directory)
#   /etc/ssh/hermes-diag.authorized_keys               the ONE allowed key, pinned to a source address
#   /etc/ssh/sshd_config.d/60-hermes-diag.conf         Match User hermes-diag: forced command, no tty/forwarding
#   /etc/sudoers.d/60-hermes-diag                      EXACT commands only; also deployed by the dotfiles pipeline from the repo
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

# ---- 2. the sudoers rules: generated from diag.py, and must equal the file the pipeline deploys ------
say "Generating the sudoers rules from diag.py"
REPO_SUDOERS="$(cd "$HERE/../.." && pwd)/sudoers/sudoers.d/60-hermes-diag"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
python3 "$HERE/gen-sudoers.py" > "$TMP"
visudo -cf "$TMP" >/dev/null || { cat "$TMP"; die "generated sudoers failed validation"; }
if [[ -f "$REPO_SUDOERS" ]]; then
  python3 "$HERE/gen-sudoers.py" --check "$REPO_SUDOERS" || die "repo sudoers file is out of date with diag.py (see message above)"
  echo "repo file sudoers/sudoers.d/60-hermes-diag matches diag.py"
else
  echo "NOTE: $REPO_SUDOERS not found; installing the generated rules only"
fi
SUDO_HOST_WANTED="$(python3 -c "import sys; sys.path.insert(0,'$HERE'); import importlib.util as u; s=u.spec_from_file_location('g','$HERE/gen-sudoers.py'); m=u.module_from_spec(s); s.loader.exec_module(m); print(m.SUDO_HOST)")"
[[ "$(hostname -s)" == "$SUDO_HOST_WANTED" ]] || echo "WARNING: this host is '$(hostname -s)' but the sudoers rule only applies to host '$SUDO_HOST_WANTED'; sudo will not grant anything here."
echo "sudoers OK"

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

say "Recording the effective sshd settings of OTHER users (to prove the drop-in does not leak)"
OTHER_USERS=("${SUDO_USER:-root}" "nobody" "someone-else")
declare -A BEFORE
for u in "${OTHER_USERS[@]}"; do
  BEFORE[$u]="$(sshd -T -C "user=$u,host=$SRC_IP,addr=$SRC_IP" 2>&1 | sort | sha256sum | cut -c1-16)"
  echo "  $u: ${BEFORE[$u]}"
done

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

say "Verifying that other users' effective sshd settings are UNCHANGED"
for u in "${OTHER_USERS[@]}"; do
  after="$(sshd -T -C "user=$u,host=$SRC_IP,addr=$SRC_IP" 2>&1 | sort | sha256sum | cut -c1-16)"
  if [[ "$after" != "${BEFORE[$u]}" ]]; then
    rm -f "$SSHD_DROPIN"
    die "sshd settings for '$u' changed (${BEFORE[$u]} -> $after): the Match block leaked. Drop-in removed, sshd NOT reloaded."
  fi
  echo "  $u: unchanged"
done

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
