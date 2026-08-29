#!/usr/bin/env bash
set -euo pipefail

PASS_CLI="$HOME/.local/bin/pass-cli"
PAT_FILE="$HOME/.secrets/proton-pass-pat"
VAULT="HOMELAB"
SOCKET="$HOME/.ssh/proton-pass-agent.sock"

export PROTON_PASS_SESSION_DIR="/tmp/pass-agent-ssh"

if ! "$PASS_CLI" info &>/dev/null; then
    PROTON_PASS_PERSONAL_ACCESS_TOKEN="$(cat "$PAT_FILE")" "$PASS_CLI" login
fi

exec "$PASS_CLI" ssh-agent start --vault-name "$VAULT" --socket-path "$SOCKET"
