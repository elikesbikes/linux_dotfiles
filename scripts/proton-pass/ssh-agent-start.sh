#!/usr/bin/env bash
set -euo pipefail

PASS_CLI="$HOME/.local/bin/pass-cli"
PAT_FILE="$HOME/.secrets/proton-pass-pat"
TPM_HANDLE="0x81010001"
VAULT="HOMELAB"
SOCKET="$HOME/.ssh/proton-pass-agent.sock"

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

if ! "$PASS_CLI" info &>/dev/null; then
    PROTON_PASS_PERSONAL_ACCESS_TOKEN="$(get_pat)" "$PASS_CLI" login
fi

exec "$PASS_CLI" ssh-agent start --vault-name "$VAULT" --socket-path "$SOCKET"
