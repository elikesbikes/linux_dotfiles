#!/usr/bin/env bash
# Update ONLY the gate program (vaultgate.py) of an existing hermes-vault install on hailmary: sudo ./update-gate.sh
# Use this after a gate change reached hailmary's dotfiles checkout (pipeline deploy-hailmary). It does not touch the
# account, the TPM-sealed PAT, sudoers or sshd (that is install.sh, which needs a fresh PAT and an empty TPM handle).
# Keeps the previous gate as vaultgate.py.prev (root-owned) so a bad update can be undone:
#   sudo install -m 0755 -o root -g root /usr/local/lib/hermes-vault/vaultgate.py.prev /usr/local/lib/hermes-vault/vaultgate.py
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "must run as root: sudo $0" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB=/usr/local/lib/hermes-vault
ACCOUNT=hermes-vault
die() { echo "ERROR: $*" >&2; exit 1; }
as_gate() { sudo -u "$ACCOUNT" env SSH_CLIENT="127.0.0.1 1 22" SSH_ORIGINAL_COMMAND="$1" "$LIB/vaultgate.py"; }

[[ "$(hostname -s)" == hailmary ]] || die "this gate is for hailmary only (this is $(hostname -s))"
[[ -f "$LIB/vaultgate.py" ]] && id "$ACCOUNT" &>/dev/null || die "no existing install: run install.sh first"
python3 -m py_compile "$HERE/vaultgate.py" && rm -rf "$HERE/__pycache__"
if cmp -s "$HERE/vaultgate.py" "$LIB/vaultgate.py"; then echo "gate already up to date"; exit 0; fi

echo "==> changes (installed -> new):"
diff -u "$LIB/vaultgate.py" "$HERE/vaultgate.py" || true
install -m 0755 -o root -g root "$LIB/vaultgate.py" "$LIB/vaultgate.py.prev"
install -m 0755 -o root -g root "$HERE/vaultgate.py" "$LIB/vaultgate.py"

echo "==> self-test as $ACCOUNT"
as_gate "help" | head -2
out="$(as_gate "create IT/github/adastra/Homelab/x.md" </dev/null || true)"
[[ "$out" == REFUSED* ]] || die "a Homelab write was not refused: $out (roll back with the command at the top)"
echo "write outside Career/Courses: $out"
echo "-- real read through Proton and CouchDB (about 15 s)"
as_gate "list IT/github/adastra/Homelab/infra/" | head -3 || die "the list test failed (roll back with the command at the top)"
echo "DONE. Previous gate kept at $LIB/vaultgate.py.prev"
