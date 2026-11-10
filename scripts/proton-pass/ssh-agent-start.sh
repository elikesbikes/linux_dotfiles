#!/usr/bin/env bash
# Proton Pass SSH agent: serves ONLY this host's own identity key.
#
# Each host signs as itself (owner rule 2026-10-09, enforced 2026-11-09): the agent loads the vault "SSH <short hostname>",
# which holds one key, "<host> SSH identity" (comment ecloaiza@<host>), and the host's PAT has viewer access to that vault.
# Targets list each host's public key in authorized_keys; nothing pins another host's key any more.
#
# Vault choice, first match wins:
#   1. ~/.config/proton-pass/ssh-agent-vault (one line): per-host override, e.g. hailmary keeps HOMELAB until the
#      SSHTars device keys move to their own agents.
#   2. "SSH <short hostname>" when that vault exists.
#   3. HOMELAB, with a syslog warning: a host not migrated yet (case, gargantua) keeps working until it gets its vault.
#
# Device mode (hailmary, SSHTars): `ssh-agent-start.sh --device <name>` serves the vault "SSH <name>" (one key titled
# "SSHTars device identity") on ~/.ssh/sshtars-<name>.sock, for the SSHTars broker to hand to that one iPhone/iPad.
# No fallback in device mode: a missing vault is an error. Run by the user unit proton-pass-ssh-agent-device@<name>.
set -euo pipefail

DEVICE=""
if [[ "${1:-}" == "--device" ]]; then
    DEVICE="${2:-}"
    [[ "$DEVICE" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || { echo "usage: $0 [--device <name>]  (name: a-z 0-9 -)" >&2; exit 2; }
fi

PASS_CLI="$HOME/.local/bin/pass-cli"
PAT_FILE="$HOME/.secrets/proton-pass-pat"
TPM_HANDLE="0x81010001"
OVERRIDE="$HOME/.config/proton-pass/ssh-agent-vault"
FALLBACK_VAULT="HOMELAB"
SOCKET="$HOME/.ssh/proton-pass-agent.sock"
TAG="proton-pass-ssh-agent"

export PROTON_PASS_KEY_PROVIDER=fs
export PROTON_PASS_SESSION_DIR="/tmp/pass-agent-ssh"

get_pat() {
    if command -v tpm2_unseal &>/dev/null && tpm2_unseal -c "$TPM_HANDLE" 2>/dev/null; then
        return
    fi
    if [[ -f "$PAT_FILE" ]]; then
        cat "$PAT_FILE"
        return
    fi
    echo "No PAT source available (TPM or $PAT_FILE)" >&2
    exit 1
}

log() { logger -p "user.$1" -t "$TAG" "$2" 2>/dev/null || true; echo "$2" >&2; }

if ! "$PASS_CLI" info &>/dev/null; then
    "$PASS_CLI" logout --force &>/dev/null || true
    PROTON_PASS_PERSONAL_ACCESS_TOKEN="$(get_pat)" "$PASS_CLI" login
fi

own_vault="SSH $(hostname -s)"
if [[ -s "$OVERRIDE" ]]; then
    VAULT="$(head -n1 "$OVERRIDE")"
    log notice "vault override from $OVERRIDE: '$VAULT'"
elif "$PASS_CLI" vault list 2>/dev/null | sed -n 's/^- \[[^]]*\]: //p' | grep -Fxq "$own_vault"; then
    VAULT="$own_vault"
else
    VAULT="$FALLBACK_VAULT"
    log warning "no vault '$own_vault' visible to this host's PAT; falling back to $FALLBACK_VAULT (host not migrated to its own SSH identity yet)"
fi

exec "$PASS_CLI" ssh-agent start --vault-name "$VAULT" --socket-path "$SOCKET"
