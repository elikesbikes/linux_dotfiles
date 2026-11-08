#!/usr/bin/env bash
# Hermes secrets helper, run by Hermes itself at start (config.yaml: secrets.command.command).
# Prints KEY=VALUE lines on stdout; the values come from Proton Pass with THIS host's own PAT
# (TPM-sealed), never from a file. Hermes discards this script's stderr and never logs the values.
# Item per host (HOMELAB vault): "honcho - API key - <host>" = a Honcho key for workspace "hermes".
set -euo pipefail
source "$HOME/scripts/proton-pass/pass-secrets.sh"
HOST="$(hostname -s)"
# pp_load: TPM-sealed cache for 10 min, Proton otherwise, up to 7-day-old cache if Proton is unreachable.
pp_load hermes-desktop "Hermes on ${HOST} (Honcho key)" \
    "HONCHO_API_KEY|honcho - API key - ${HOST}|password" >&2
printf 'HONCHO_API_KEY=%s\n' "$HONCHO_API_KEY"
