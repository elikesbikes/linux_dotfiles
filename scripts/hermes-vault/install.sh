#!/usr/bin/env bash
# Install the `hermes-vault` SSH account on hailmary (run as root: sudo ./install.sh). See README.md.
#
# Creates, all root-owned so the account cannot change its own restrictions:
#   user              hermes-vault  (no password; NOT in docker/sudo/adm/tss; shell only starts the forced command)
#   /usr/local/lib/hermes-vault/{vaultgate.py,unseal-pat,pass-cli}   the gate, the TPM helper, a pinned pass-cli
#   TPM handle 0x81010002                               this account's OWN Proton Pass PAT (asked for, never echoed)
#   /etc/ssh/hermes-vault.authorized_keys               the ONE allowed key, pinned to endurance's address
#   /etc/ssh/sshd_config.d/61-hermes-vault.conf         Match User hermes-vault: forced command, no tty/forwarding
#   /etc/sudoers.d/60-hermes-vault                      ONE exact command (unseal-pat, no arguments)
# Everything is validated BEFORE it is activated; uninstall.sh removes it all.
#
# Usage: sudo ./install.sh [pubkey-file] [allowed-source-ip]
#   pubkey-file  default: the key already trusted for hermes-diag (Hermes' container key)
#   source-ip    default: 192.168.5.46 (endurance)
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "must run as root: sudo $0 [pubkey-file] [source-ip]" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_IP="${2:-192.168.5.46}"
ACCOUNT=hermes-vault
LIB=/usr/local/lib/hermes-vault
AUTH=/etc/ssh/hermes-vault.authorized_keys
SSHD_DROPIN=/etc/ssh/sshd_config.d/61-hermes-vault.conf
SUDOERS=/etc/sudoers.d/60-hermes-vault
REPO_SUDOERS="$(cd "$HERE/../.." && pwd)/sudoers/sudoers.d/60-hermes-vault"
HANDLE=0x81010002
OWNER_HANDLE=0x81010001
OWNER="${SUDO_USER:-ecloaiza}"
PASS_CLI_SRC="$(getent passwd "$OWNER" | cut -d: -f6)/.local/bin/pass-cli"

say() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
as_gate() { sudo -u "$ACCOUNT" env SSH_CLIENT="127.0.0.1 1 22" SSH_ORIGINAL_COMMAND="$1" "$LIB/vaultgate.py"; }

TMPD="$(mktemp -d /dev/shm/hermes-vault-install.XXXXXX)"; chmod 700 "$TMPD"
trap 'rm -rf "$TMPD"' EXIT

# ---- 1. validate inputs (nothing has been changed yet) -------------------------------------------
say "Validating inputs"
[[ "$(hostname -s)" == hailmary ]] || die "this gate is for hailmary only (this is $(hostname -s))"
for f in vaultgate.py unseal-pat uninstall.sh; do [[ -f "$HERE/$f" ]] || die "$f not found next to this script"; done
python3 -m py_compile "$HERE/vaultgate.py"
if [[ -n "${1:-}" ]]; then
  PUBFILE="$1"
else
  PUBFILE="$TMPD/key.pub"
  grep -o 'ssh-ed25519 [A-Za-z0-9+/=]*' /etc/ssh/hermes-diag.authorized_keys > "$PUBFILE" \
    || die "no pubkey given and none found in /etc/ssh/hermes-diag.authorized_keys"
fi
[[ -f "$PUBFILE" && $(grep -c . "$PUBFILE") -eq 1 ]] || die "the key file must contain exactly ONE key"
KEYLINE="$(cat "$PUBFILE")"
[[ "$KEYLINE" == ssh-ed25519\ * && "$KEYLINE" != *\"* ]] || die "only a plain ssh-ed25519 key line is accepted"
ssh-keygen -lf "$PUBFILE" >/dev/null || die "not a valid public key"
[[ "$SRC_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "source must be a single IPv4 address"
for t in tpm2_createprimary tpm2_create tpm2_load tpm2_evictcontrol tpm2_unseal tpm2_getcap; do
  command -v "$t" >/dev/null || die "$t missing (apt install tpm2-tools)"
done
[[ -x "$PASS_CLI_SRC" ]] || die "pass-cli not found at $PASS_CLI_SRC"
if tpm2_getcap handles-persistent | grep -qi "$HANDLE"; then
  die "TPM handle $HANDLE is already in use. If it is an old hermes-vault PAT: sudo tpm2_evictcontrol -C o -c $HANDLE, then re-run."
fi
[[ -f "$REPO_SUDOERS" ]] || die "repo sudoers file missing: $REPO_SUDOERS"
visudo -cf "$REPO_SUDOERS" >/dev/null || die "repo sudoers file failed validation"
echo "key: $(ssh-keygen -lf "$PUBFILE")  allowed only from: $SRC_IP"

say "Paste the token of the Proton Pass PAT 'hailmary-hermes-vault' (input is hidden), then Enter"
read -rs PAT; echo
[[ -n "$PAT" && "$PAT" != *[[:space:]]* ]] || die "empty token or token with spaces"

# ---- 2. account + files ------------------------------------------------------------------------
say "Creating account $ACCOUNT"
if id "$ACCOUNT" &>/dev/null; then
  echo "already exists"
else
  # '*' = no valid password but NOT locked, so key auth still works under UsePAM.
  useradd --create-home --shell /bin/sh --comment "Hermes vault capture (create-only)" --password '*' "$ACCOUNT"
fi
for g in docker sudo adm systemd-journal root tss; do
  if id -nG "$ACCOUNT" | tr ' ' '\n' | grep -qx "$g"; then die "$ACCOUNT must not be in group $g"; fi
done
chmod 0700 "$(getent passwd "$ACCOUNT" | cut -d: -f6)"

say "Installing the gate, the TPM helper and a pinned pass-cli (root-owned)"
install -d -m 0755 -o root -g root "$LIB"
install -m 0755 -o root -g root "$HERE/vaultgate.py" "$LIB/vaultgate.py"
install -m 0755 -o root -g root "$HERE/unseal-pat" "$LIB/unseal-pat"
install -m 0755 -o root -g root "$PASS_CLI_SRC" "$LIB/pass-cli"
"$LIB/pass-cli" --version

say "Installing sudoers (the repo file, validated)"
install -m 0440 -o root -g root "$REPO_SUDOERS" "$SUDOERS"
visudo -c >/dev/null

# ---- 3. seal the PAT -----------------------------------------------------------------------------
say "Sealing the PAT at TPM handle $HANDLE (the owner's $OWNER_HANDLE is not touched)"
OWNER_BEFORE="$(tpm2_getcap handles-persistent | grep -ci "$OWNER_HANDLE" || true)"
( cd "$TMPD"
  tpm2_createprimary -Q -C o -g sha256 -G rsa -c primary.ctx
  printf '%s' "$PAT" | tpm2_create -Q -C primary.ctx -i - -u sealed.pub -r sealed.priv
  tpm2_load -Q -C primary.ctx -u sealed.pub -r sealed.priv -c sealed.ctx
  tpm2_evictcontrol -Q -C o -c sealed.ctx "$HANDLE" >/dev/null )
unset PAT
[[ "$(sudo -u "$ACCOUNT" sudo -n "$LIB/unseal-pat" | wc -c)" -gt 10 ]] || die "the account cannot read its PAT through the helper"
[[ "$(tpm2_getcap handles-persistent | grep -ci "$OWNER_HANDLE" || true)" == "$OWNER_BEFORE" ]] || die "owner handle changed?!"
if sudo -u "$ACCOUNT" /usr/bin/tpm2_unseal -c "$OWNER_HANDLE" >/dev/null 2>&1; then
  die "ISOLATION FAILURE: $ACCOUNT can unseal the owner's PAT at $OWNER_HANDLE. Stop and investigate."
fi
if sudo -u "$ACCOUNT" sudo -n "$LIB/unseal-pat" -c "$OWNER_HANDLE" >/dev/null 2>&1; then
  die "ISOLATION FAILURE: the helper accepted arguments. Stop and investigate."
fi
echo "isolation OK: $ACCOUNT reads only $HANDLE (helper, no arguments); $OWNER_HANDLE refused"

# ---- 4. ssh ----------------------------------------------------------------------------------------
say "Installing the authorized key (root-owned, pinned to $SRC_IP)"
printf 'from="%s",restrict,command="%s/vaultgate.py" %s\n' "$SRC_IP" "$LIB" "$KEYLINE" > "$AUTH"
chown root:root "$AUTH"; chmod 0644 "$AUTH"

say "Recording the effective sshd settings of OTHER users (to prove the drop-in does not leak)"
OTHER_USERS=("$OWNER" "hermes-diag" "nobody")
declare -A BEFORE
for u in "${OTHER_USERS[@]}"; do
  BEFORE[$u]="$(sshd -T -C "user=$u,host=$SRC_IP,addr=$SRC_IP" 2>&1 | sort | sha256sum | cut -c1-16)"
done

say "Installing sshd restrictions"
cat > "$SSHD_DROPIN" <<EOF
# Managed by scripts/hermes-vault/install.sh
Match User $ACCOUNT
    AuthorizedKeysFile $AUTH
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    ForceCommand $LIB/vaultgate.py
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
for u in "${OTHER_USERS[@]}"; do
  after="$(sshd -T -C "user=$u,host=$SRC_IP,addr=$SRC_IP" 2>&1 | sort | sha256sum | cut -c1-16)"
  [[ "$after" == "${BEFORE[$u]}" ]] || { rm -f "$SSHD_DROPIN"; die "sshd settings for '$u' changed: the Match block leaked. Drop-in removed, sshd NOT reloaded."; }
  echo "  $u: unchanged"
done
EFF="$(sshd -T -C "user=$ACCOUNT,host=$SRC_IP,addr=$SRC_IP" 2>&1)"
grep -qi "^forcecommand $LIB/vaultgate.py" <<<"$EFF" || { rm -f "$SSHD_DROPIN"; die "ForceCommand is not in effect; drop-in removed"; }
grep -qi "^permittty no" <<<"$EFF" || { rm -f "$SSHD_DROPIN"; die "PermitTTY is not 'no'; drop-in removed"; }

say "Reloading sshd (existing sessions are kept)"
systemctl reload ssh 2>/dev/null || systemctl reload sshd

# ---- 5. self-test ------------------------------------------------------------------------------------
say "Self-test of the gate as $ACCOUNT"
as_gate "help" | head -3
as_gate "delete Career/Courses/x.md" || true
as_gate "create Finances/x.md" </dev/null || true
echo "-- real test: Proton login with the new PAT + list the course notes (about 15 s)"
as_gate "list Career/Courses/" | head -5 || die "the list test failed (see the FAILED line above)"

echo
echo "DONE. Remove with: sudo $HERE/uninstall.sh"
