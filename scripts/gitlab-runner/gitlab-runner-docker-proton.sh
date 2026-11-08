#!/usr/bin/env bash
# Docker-executor GitLab Runner (a container) whose token never touches disk.
#
# The container mounts a tmpfs (RAM) at /etc/gitlab-runner and starts without a config. This script,
# run by the systemd user service gitlab-runner-docker-proton.service, reads the token from Proton Pass
# (HOMELAB item "gitlab-runner token - <short hostname>-docker") with the host's TPM-sealed PAT, fills
# it into docker-<short hostname>.toml (next to this file, placeholder @TOKEN@) and pipes the result
# into the container through `docker exec` stdin. It does that once at start and again every time the
# container starts (docker events), because a restarted container comes back with an empty tmpfs.
# The token is fetched fresh each time and is never kept in this process between injections.
#
# Usage: gitlab-runner-docker-proton.sh [container name, default gitlab-runner]
set -euo pipefail

HOST="$(hostname -s)"
CONTAINER="${1:-gitlab-runner}"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
TEMPLATE="$HERE/docker-$HOST.toml"
PASS_CLI="$HOME/.local/bin/pass-cli"
TPM_HANDLE="0x81010001"
VAULT="HOMELAB"
ITEM="gitlab-runner token - $HOST-docker"
RUN_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gitlab-runner-docker"

export PROTON_PASS_KEY_PROVIDER=fs
export PROTON_PASS_SESSION_DIR="$RUN_DIR/pass-session"
export PROTON_PASS_AGENT_REASON="Configuring GitLab Runner container on $HOST"

umask 077
mkdir -p "$RUN_DIR"
[ -r "$TEMPLATE" ] || { echo "missing template $TEMPLATE" >&2; exit 1; }
grep -q '@TOKEN@' "$TEMPLATE" || { echo "template has no @TOKEN@ placeholder" >&2; exit 1; }

log() { echo "gitlab-runner-docker-proton: $*"; }

wait_running() {  # up to 10 minutes; systemd restarts the service if it gives up
    for _ in $(seq 1 120); do
        [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ] && return 0
        sleep 5
    done
    log "container $CONTAINER is not running"; return 1
}

inject() {
    local pat token config
    pat="$(tpm2_unseal -c "$TPM_HANDLE" 2>/dev/null)" || { log "TPM unseal failed"; return 1; }
    PROTON_PASS_PERSONAL_ACCESS_TOKEN="$pat" "$PASS_CLI" login >/dev/null
    pat=""
    token="$("$PASS_CLI" item view --vault-name "$VAULT" --item-title "$ITEM" --field note)"
    "$PASS_CLI" logout >/dev/null 2>&1 || true
    rm -rf "$PROTON_PASS_SESSION_DIR"
    [[ ${#token} -ge 20 && "$token" != *[[:space:]]* ]] || { log "Proton item '$ITEM' is missing or not a runner token"; return 1; }
    config="$(cat "$TEMPLATE")"
    config="${config//@TOKEN@/$token}"
    token=""
    printf '%s\n' "$config" | docker exec -i "$CONTAINER" sh -c \
        'umask 077; cat > /etc/gitlab-runner/config.toml.new && mv -f /etc/gitlab-runner/config.toml.new /etc/gitlab-runner/config.toml'
    config=""
    log "config written into $CONTAINER (tmpfs)"
}

wait_running
inject
# Re-inject after every container start (restart, recreate, daemon restart).
docker events --filter "container=$CONTAINER" --filter event=start --format '{{.Status}}' |
while read -r _; do
    sleep 2
    wait_running && inject || log "re-inject failed; will retry on the next start or service restart"
done
