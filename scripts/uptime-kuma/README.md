# uptime-kuma

`mcp-start.sh` starts the Uptime Kuma MCP server (`~/devops/mcp/uptime-kuma/server.js`) for Claude Code. It is registered as the `uptime-kuma` stdio server in `.claude/settings.json`.

## Why it exists

- `uptime.home.elikesbikes.com` is behind Authelia, so the server's Socket.IO login through Traefik gets a 302 to the auth portal and never connects. The server was also registered with no `env`, so it exited at start. That is why the MCP tools were missing (found 2026-11-27).
- The password must not sit in `settings.json` or any other file, so the script loads it from Proton Pass (`uptimekuma - UPTIME_KUMA_PASSWORD`, HOMELAB, `note` field) at start.

## What it does

1. Loads `UPTIME_KUMA_PASSWORD` with `pp_load`.
2. Looks up the `uptime-prod-1` container's IP on hailmary's `frontend` network. The container has no published port.
3. Opens an SSH tunnel from `127.0.0.1:<free port>` to `<container IP>:3001`.
4. Runs the server against the tunnel. The tunnel is killed when the server exits.

## Gotchas

- Nothing may print to stdout, because stdout is the MCP protocol channel.
- Nothing before `node` may read stdin. `ssh` without `-n` (and `pp_load`) swallowed the client's `initialize` message, and the server never answered. Both now get `</dev/null`.

## Tested (2026-11-27, tars)

`initialize` answered in 3.0 s. `tools/list` returns all 9 tools, and `get_monitor` and `list_monitors` return live data. No tunnel process is left after exit. Claude Code itself only picks it up after a session restart; not yet checked in a new session.
