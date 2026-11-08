#!/usr/bin/env bash
# GitLab Runner for no-secrets hosts (first user: murph sandbox).
#
# The runner token lives only in Proton Pass (HOMELAB item "gitlab-runner token - <short hostname>").
# At every start this script unseals the host's own PAT from the TPM, reads the token, writes
# config.toml to $XDG_RUNTIME_DIR (RAM, gone at reboot/logout), logs pass-cli out again and execs the
# runner. Nothing secret is written to disk. Run it from a systemd user service, see
# gitlab-runner-proton.service next to this file.
#
# Hosts that may keep a token on disk (rocky, hailmary) use the plain ~/.gitlab-runner/config.toml instead.
set -euo pipefail

HOST="$(hostname -s)"
PASS_CLI="$HOME/.local/bin/pass-cli"
RUNNER="$HOME/.local/bin/gitlab-runner"
TPM_HANDLE="0x81010001"
VAULT="HOMELAB"
ITEM="gitlab-runner token - $HOST"
RUN_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gitlab-runner"
CONF="$RUN_DIR/config.toml"

export PROTON_PASS_KEY_PROVIDER=fs
export PROTON_PASS_SESSION_DIR="$RUN_DIR/pass-session"
export PROTON_PASS_AGENT_REASON="Starting GitLab Runner on $HOST"

umask 077
mkdir -p "$RUN_DIR"

pat="$(tpm2_unseal -c "$TPM_HANDLE" 2>/dev/null)" || { echo "No PAT: TPM unseal failed ($HOST keeps no plaintext PAT)" >&2; exit 1; }
PROTON_PASS_PERSONAL_ACCESS_TOKEN="$pat" "$PASS_CLI" login >/dev/null
unset pat
token="$("$PASS_CLI" item view --vault-name "$VAULT" --item-title "$ITEM" --field note)"
"$PASS_CLI" logout >/dev/null 2>&1 || true
rm -rf "$PROTON_PASS_SESSION_DIR"
[[ "$token" == glrt-* ]] || { echo "Proton item '$ITEM' is missing or not a runner token" >&2; exit 1; }

cat > "$CONF" <<EOF
concurrent = 1
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "$HOST-shell"
  url = "https://gitlab.home.elikesbikes.com"
  token = "$token"
  executor = "shell"
  # 1 (the default) makes the runner log a "long polling issues" warning at every start
  request_concurrency = 2
EOF
unset token

exec "$RUNNER" run --config "$CONF" --working-directory "$HOME"
