#!/usr/bin/env bash
# Give the existing `hermes-diag` account on hailmary its OWN MCC runner key (run as root: sudo ./enable-mcc-key.sh).
#
# Since MCC security audit run 4 (2026-11-12) the runner wants a key from every local caller, so `status`,
# `component` and `fit` get 401 without one. The account reads `MCC - MCC_TOKEN_HERMES_DIAG` with its OWN Proton
# Pass PAT (owner's rule: one PAT per host and user), the same pattern as scripts/hermes-vault:
#
#   /usr/local/lib/hermes-diag/{diag.py,unseal-pat,pass-cli}   the gate (current repo copy), the TPM helper, a pinned pass-cli
#   TPM handle 0x81010003                                  this account's OWN PAT (asked for, never echoed)
#   /etc/sudoers.d/60-hermes-diag                          the repo file: the read-only commands plus ONE exact
#                                                          command for the helper, no arguments
#
# The account stays out of the tss group, so it can never unseal the owner's PAT (0x81010001) or hermes-vault's
# (0x81010002); this script proves it. Everything is validated BEFORE anything changes. The old diag.py is kept as
# diag.py.prev. Undo: sudo tpm2_evictcontrol -C o -c 0x81010003; sudo rm -rf /usr/local/lib/hermes-diag/{unseal-pat,pass-cli}
# ~hermes-diag/.pp-session; restore diag.py.prev; revoke the PAT.
#
# Usage: sudo ./enable-mcc-key.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "must run as root: sudo $0" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT=hermes-diag
LIB=/usr/local/lib/hermes-diag
SUDOERS=/etc/sudoers.d/60-hermes-diag
REPO_SUDOERS="$(cd "$HERE/../.." && pwd)/sudoers/sudoers.d/60-hermes-diag"
HANDLE=0x81010003
OTHER_HANDLES=(0x81010001 0x81010002)
OWNER="${SUDO_USER:-ecloaiza}"
PASS_CLI_SRC="$(getent passwd "$OWNER" | cut -d: -f6)/.local/bin/pass-cli"

say() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
as_gate() { sudo -H -u "$ACCOUNT" env SSH_CLIENT="127.0.0.1 1 22" SSH_ORIGINAL_COMMAND="$1" /usr/bin/python3 "$LIB/diag.py"; }

TMPD="$(mktemp -d /dev/shm/hermes-diag-key.XXXXXX)"; chmod 700 "$TMPD"
trap 'rm -rf "$TMPD"' EXIT

# ---- 1. validate (nothing has been changed yet) ----------------------------------------------------
say "Validating"
[[ "$(hostname -s)" == hailmary ]] || die "the MCC key is for hailmary only (this is $(hostname -s))"
id "$ACCOUNT" &>/dev/null || die "account $ACCOUNT does not exist: run install.sh first"
for g in docker sudo adm systemd-journal root tss; do
  if id -nG "$ACCOUNT" | tr ' ' '\n' | grep -qx "$g"; then die "$ACCOUNT must not be in group $g"; fi
done
for f in diag.py unseal-pat gen-sudoers.py; do [[ -f "$HERE/$f" ]] || die "$f not found next to this script"; done
python3 -m py_compile "$HERE/diag.py"
grep -q "^exec /usr/bin/tpm2_unseal -c $HANDLE\$" "$HERE/unseal-pat" || die "unseal-pat does not name handle $HANDLE"
for t in tpm2_createprimary tpm2_create tpm2_load tpm2_evictcontrol tpm2_unseal tpm2_getcap visudo; do
  command -v "$t" >/dev/null || die "$t missing (apt install tpm2-tools)"
done
[[ -x "$PASS_CLI_SRC" ]] || die "pass-cli not found at $PASS_CLI_SRC"
if tpm2_getcap handles-persistent | grep -qi "$HANDLE"; then
  die "TPM handle $HANDLE is already in use. If it is an old hermes-diag PAT: sudo tpm2_evictcontrol -C o -c $HANDLE, then re-run."
fi
[[ -f "$REPO_SUDOERS" ]] || die "repo sudoers file missing: $REPO_SUDOERS"
python3 "$HERE/gen-sudoers.py" --check "$REPO_SUDOERS" || die "repo sudoers file is out of date with diag.py"
visudo -cf "$REPO_SUDOERS" >/dev/null || die "repo sudoers file failed validation"
grep -q "NOPASSWD: $LIB/unseal-pat \"\"\$" "$REPO_SUDOERS" || die "repo sudoers file has no rule for $LIB/unseal-pat"

say "Paste the token of the Proton Pass PAT 'hailmary-hermes-diag' (input is hidden), then Enter"
read -rs PAT; echo
[[ -n "$PAT" && "$PAT" != *[[:space:]]* ]] || die "empty token or token with spaces"

# ---- 2. files ----------------------------------------------------------------------------------------
say "Installing the gate, the TPM helper and a pinned pass-cli (root-owned)"
install -d -m 0755 -o root -g root "$LIB"
[[ -f "$LIB/diag.py" ]] && install -m 0755 -o root -g root "$LIB/diag.py" "$LIB/diag.py.prev"
install -m 0755 -o root -g root "$HERE/diag.py" "$LIB/diag.py"
install -m 0755 -o root -g root "$HERE/unseal-pat" "$LIB/unseal-pat"
install -m 0755 -o root -g root "$PASS_CLI_SRC" "$LIB/pass-cli"
"$LIB/pass-cli" --version

say "Installing sudoers (the repo file, validated; the dotfiles pipeline deploys the same file)"
install -m 0440 -o root -g root "$REPO_SUDOERS" "$SUDOERS"
visudo -c >/dev/null

# ---- 3. seal the PAT -----------------------------------------------------------------------------------
say "Sealing the PAT at TPM handle $HANDLE (${OTHER_HANDLES[*]} are not touched)"
declare -A BEFORE
for h in "${OTHER_HANDLES[@]}"; do BEFORE[$h]="$(tpm2_getcap handles-persistent | grep -ci "$h" || true)"; done
( cd "$TMPD"
  tpm2_createprimary -Q -C o -g sha256 -G rsa -c primary.ctx
  printf '%s' "$PAT" | tpm2_create -Q -C primary.ctx -i - -u sealed.pub -r sealed.priv
  tpm2_load -Q -C primary.ctx -u sealed.pub -r sealed.priv -c sealed.ctx
  tpm2_evictcontrol -Q -C o -c sealed.ctx "$HANDLE" >/dev/null )
unset PAT
[[ "$(sudo -u "$ACCOUNT" sudo -n "$LIB/unseal-pat" | wc -c)" -gt 10 ]] || die "the account cannot read its PAT through the helper"
for h in "${OTHER_HANDLES[@]}"; do
  [[ "$(tpm2_getcap handles-persistent | grep -ci "$h" || true)" == "${BEFORE[$h]}" ]] || die "handle $h changed?!"
  if sudo -u "$ACCOUNT" /usr/bin/tpm2_unseal -c "$h" >/dev/null 2>&1; then
    die "ISOLATION FAILURE: $ACCOUNT can unseal $h. Stop and investigate."
  fi
  if sudo -u "$ACCOUNT" sudo -n "$LIB/unseal-pat" -c "$h" >/dev/null 2>&1; then
    die "ISOLATION FAILURE: the helper accepted arguments. Stop and investigate."
  fi
done
echo "isolation OK: $ACCOUNT reads only $HANDLE (helper, no arguments); ${OTHER_HANDLES[*]} refused"

# ---- 4. self-test through the real gate ---------------------------------------------------------------
say "Self-test as $ACCOUNT: Proton login with the new PAT, then the MCC runner with the account's own key"
OUT="$(as_gate status)" || { echo "$OUT" | head -5; die "status failed (see above)"; }
echo "$OUT" | head -3
OUT="$(as_gate "fit readiness")" || { echo "$OUT" | head -5; die "fit readiness failed (see above)"; }
echo "$OUT" | head -2
echo
echo "DONE. The account's MCC commands work again. Undo: see the comment at the top of this script."
