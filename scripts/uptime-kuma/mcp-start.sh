#!/usr/bin/env bash
# Start the Uptime Kuma MCP server (stdio) for Claude Code.
#
# Why a wrapper (2026-11-27):
#   - uptime.home.elikesbikes.com is behind Authelia, so the server's Socket.IO login
#     through Traefik gets a 302 to the auth portal and never connects.
#   - The password must not sit in settings.json or any file (no plaintext secrets rule),
#     so it is loaded from Proton Pass at start.
# What it does: loads UPTIME_KUMA_PASSWORD from Proton Pass, opens a private SSH tunnel
# from 127.0.0.1:<free port> to the uptime-prod-1 container on hailmary, then runs the
# server against the tunnel. The tunnel is closed when the server exits.
# Nothing may be printed to stdout (the MCP protocol channel), and nothing before node may
# read stdin (ssh and pp_load get </dev/null), or the client's first message is lost.
set -euo pipefail

SERVER=/home/ecloaiza/devops/mcp/uptime-kuma/server.js
log() { echo "uptime-kuma-mcp: $*" >&2; }

export PROTON_PASS_AGENT_REASON="uptime-kuma MCP server on $(hostname -s)"
# shellcheck source=/dev/null
source "$HOME/scripts/proton-pass/pass-secrets.sh"
pp_load claude-uptime-kuma-mcp "Uptime Kuma MCP" \
  "UPTIME_KUMA_PASSWORD|uptimekuma - UPTIME_KUMA_PASSWORD|note" </dev/null >/dev/null 2>&1 \
  || { log "could not load UPTIME_KUMA_PASSWORD from Proton Pass"; exit 1; }
export UPTIME_KUMA_PASSWORD

# The container has no published port; find its address on the frontend network.
ip=$(ssh -n -o BatchMode=yes -o ConnectTimeout=8 hailmary \
  'docker inspect -f "{{(index .NetworkSettings.Networks \"frontend\").IPAddress}}" uptime-prod-1' 2>/dev/null) \
  || { log "could not look up uptime-prod-1 on hailmary"; exit 1; }
[ -n "$ip" ] || { log "uptime-prod-1 has no frontend IP"; exit 1; }

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
ssh -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -N \
  -L "127.0.0.1:${port}:${ip}:3001" hailmary </dev/null >/dev/null 2>&1 &
tunnel=$!
trap 'kill "$tunnel" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null && break
  kill -0 "$tunnel" 2>/dev/null || { log "SSH tunnel to hailmary failed"; exit 1; }
  python3 -c 'import time; time.sleep(0.2)'
done

export UPTIME_KUMA_URL="http://127.0.0.1:${port}"
export UPTIME_KUMA_USERNAME=ecloaiza
node "$SERVER"
