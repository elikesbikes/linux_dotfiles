#!/usr/bin/env bash
# Proton Pass SSH agent for this host, from the HOMELAB vault (folder "SSH").
#
# Since v1.17.0 (2026-11-12, owner decision) every SSH key lives in HOMELAB, folder "SSH": one key per host,
# "<host> SSH identity" (comment ecloaiza@<host>), plus the SSHTars device keys. pass-cli 2.7.0's agent can only filter
# by vault, so the agent serves EVERY SSH key in HOMELAB. Each host still signs only as itself because ~/.ssh/config
# pins the host's own public key under Host *:  IdentityFile ~/.ssh/identity.pub + IdentitiesOnly yes.
# Anything that uses this socket without that config (e.g. a container mounting it) must pin identity.pub too.
#
# Vault choice: ~/.config/proton-pass/ssh-agent-vault (one line) if present, else HOMELAB.
#
# Device mode (hailmary, SSHTars): `ssh-agent-start.sh --device <name>` serves the same HOMELAB keys on
# ~/.ssh/sshtars-<name>.sock, for the SSHTars broker to hand to that one iPhone/iPad. The device's own key is
# "SSHTars <name> identity"; the broker's catalog names it per device. Run by the user unit
# proton-pass-ssh-agent-device@<name>.
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
VAULT_DEFAULT="HOMELAB"
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

if [[ -n "$DEVICE" ]]; then
    SOCKET="$HOME/.ssh/sshtars-$DEVICE.sock"
    rm -f "$SOCKET"
    exec "$PASS_CLI" ssh-agent start --vault-name "$VAULT_DEFAULT" --socket-path "$SOCKET"
fi

if [[ -s "$OVERRIDE" ]]; then
    VAULT="$(head -n1 "$OVERRIDE")"
    log notice "vault override from $OVERRIDE: '$VAULT'"
else
    VAULT="$VAULT_DEFAULT"
fi

exec "$PASS_CLI" ssh-agent start --vault-name "$VAULT" --socket-path "$SOCKET"
