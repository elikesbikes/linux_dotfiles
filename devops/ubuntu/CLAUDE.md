# Homelab Reference

## Hosts

| Hostname | IP | OS | Role | Hardware | TPM | Notes |
|----------|-----|-----|------|----------|-----|-------|
| **tars** | 192.168.5.127 | Arch (Omarchy) | Desktop workstation | ASUS ROG STRIX B550-F, NVIDIA Quadro P4000 | fTPM, sealed | Primary desktop. /home is btrfs @home, NOT snapshotted. No Flatpak. |
| **rocky** | 192.168.5.28 | Ubuntu 26.04 | Dev server (Docker) | Proxmox VM | Pending | Replaced tars for all Docker/dev work (2026-08-31). All services migrated. |
| **case** | ssh case | Arch (Omarchy) | Desktop | Lenovo ThinkPad 20XY002KUS | Physical 2.0, sealed | LUKS-encrypted. Proton Pass fully configured. |
| **ranger** | ssh ranger | Arch (Omarchy) | Desktop | Lenovo ThinkPad 20UES2KW0Y | Physical 2.0, sealed | LUKS-encrypted. Proton Pass fully configured. |
| **trainerroad** | ssh trainerroad | Arch (Omarchy) | Desktop | HP desktop 83EE | Physical 2.0, sealed | Proton Pass fully configured. No ProtonVPN. |
| **gargantua** | 192.168.5.109 | Ubuntu 26.04 | Workstation | — | — | sudo-rs (no log_output/iolog_dir). Proton suite fully installed. |
| **hailmary** | 192.168.5.25 | Ubuntu 26.04 | Server (Proxmox VM, UEFI) | — | vTPM pending | Runs Graylog (syslog 514/udp) + CouchDB (Obsidian LiveSync). |
| **endurance** | 192.168.5.162 | — | Server (Proxmox VM) | — | vTPM, sealed | Former syslog host. SSH key in vault. |
| **archlinux** | 192.168.5.233 | Arch (Hyprland) | Experimental | — | — | Vanilla Hyprland (not Omarchy). Quickshell bar stalled on Qt Wayland. |

### Network infrastructure

- **UniFi Router** — 192.168.5.1, SSH via RSA key in Proton Pass HOMELAB vault
- **Domain** — `home.elikesbikes.com` (internal DNS via UniFi)
- **GitLab** — `gitlab.home.elikesbikes.com` (self-hosted, user: ecloaiza)
- **GitHub** — user: elikesbikes

## Services on Rocky (primary dev server)

All Docker services at `~/devops/docker/` on rocky. DNS is CNAME → `rocky.home.elikesbikes.com`.

| Service | Hostname / Port | Notes |
|---------|----------------|-------|
| Traefik | proxy-rocky.home.elikesbikes.com | Reverse proxy, dashboard with basic auth |
| Socket Proxy | socketproxy-rocky.home.elikesbikes.com | Docker socket proxy for Traefik |
| Authelia + Redis | auth-rocky.home.elikesbikes.com | SSO/2FA portal |
| n8n | port 5678 (direct, no Traefik) | Workflow automation, custom Dockerfile |
| Ansible Semaphore + MySQL + MCP | ansible-rocky / ansible-mcp-rocky | MCP pinned to `mcp[cli]<2` |
| Graylog + MongoDB + OpenSearch | graylog-rocky.home.elikesbikes.com | MongoDB 4.4 (CPU lacks AVX) |
| Restic | restic-rocky.home.elikesbikes.com | Backup, local dir (NFS pending) |
| Reverie | reviere-rocky.home.elikesbikes.com | Behind Authelia two_factor |

## Services on Hailmary

| Service | Port | Notes |
|---------|------|-------|
| Graylog | 514/udp | Centralized syslog for all Docker services |
| CouchDB | — | Obsidian Self-hosted LiveSync backend |

## MCP Servers (Claude Code)

All registered globally in `~/.claude/settings.json`.

| Server | Type | URL / Command |
|--------|------|---------------|
| unifi | SSE (n8n) | `http://192.168.5.30:5678/mcp/a65e26aa.../sse` |
| graylog-wifi | SSE (n8n) | `http://192.168.5.30:5678/mcp/graylog-wifi-mcp/sse` |
| n8n-mcp | stdio | `npx -y n8n-mcp` |
| uptime-kuma | stdio | `node ~/devops/mcp/uptime-kuma/server.js` |
| ansible | SSE | `https://ansible-mcp.home.elikesbikes.com/sse` |

## Directory Layout

| Path | Purpose |
|------|---------|
| `~/devops/` | Main development workspace |
| `~/devops/docker/` | All Docker project directories (n8n, traefik, authelia, graylog, ansible, restic, etc.) |
| `~/devops/github/adastra/` | Homelab documentation repo (GitLab only) |
| `~/devops/github/linux_dotfiles/` | Dotfiles repo (GitHub + GitLab) |
| `~/scripts/<topic>/` | Custom scripts (certbot, proton-pass, etc.) |
| `~/.secrets/` | Secrets only (PAT, cloudflare.ini, etc.) |
| `~/.claude/skills` | Symlink → `~/devops/github/adastra/AI/skills/` |

## Adastra Repo (Homelab Docs)

- **Location:** `~/devops/github/adastra`
- **Remote:** `https://gitlab.home.elikesbikes.com/ecloaiza/adastra.git`
- **Content:** AI prompts/templates, Claude skills, HomeAssistant, Proxmox, network, UPS, Linux/Unison docs
- **Services markdown:** Obsidian Database Folder views at `IT/github/adastra/Homelab/` — `ipam/`, `services/`, `infra/` (each has a `.base` file)
- **Commit/push:** Use `gacp_adastra` function (also syncs to Obsidian via `syncn`)

## Obsidian Vault

- **Path:** `~/Documents/Obsidian/Loaiza/` — NEVER read or write locally
- **All access via CouchDB on hailmary:** `ssh hailmary "cd /home/ecloaiza/devops/projects/mcc && python3 tools/vault_fetch.py --get|--put|--list '<path>'"`
- **Sync:** Self-hosted LiveSync via CouchDB on hailmary
- **Homelab views:** `IT/github/adastra/Homelab/` — IPAM, services, infra databases

## Security / Secrets Management

### Proton Pass

- **Vaults:** Emmanuel Vault (personal), Family, Escuincles, Career, HOMELAB
- **SSH Agent:** systemd service, 7 keys in HOMELAB vault, socket at `~/.ssh/proton-pass-agent.sock`
- **PAT:** stored at `~/.secrets/proton-pass-pat` (or TPM-sealed at handle `0x81010001`)
- **Git credentials:** `~/scripts/proton-pass/git-credential-protonpass` handles github.com + gitlab.home.elikesbikes.com
- **Docker secrets:** `start.sh` per service — PAT login → `pass-cli item view` → export → docker compose

### TPM-Sealed PAT Status

| Host | Status |
|------|--------|
| tars, case, endurance, ranger, trainerroad | Done (handle `0x81010001`) |
| rocky | Pending |
| hailmary | Pending (vTPM needed) |

### Certbot / TLS

- **Scripts:** `~/scripts/certbot/`
- **Cloudflare token:** `~/.secrets/certbot/cloudflare.ini`
- **Target:** `router.home.elikesbikes.com` (UniFi router), DNS-01 via Cloudflare
- **Deploy hook:** copies cert to router via SSH agent (not automated, manual renewal)

## Key Bash Functions & Aliases

Defined in `~/devops/github/linux_dotfiles/.bash/`:

- `gacp_adastra` — commit/push adastra + sync to Obsidian
- `gacp_dotfiles` — commit/push linux_dotfiles, optional `--tag`
- `syncn` — rsync + unison sync of `~/devops/github/` markdown to Obsidian
- `claudepower` — launches Claude in auto-mode from `~/devops/ubuntu`
- `claudedocker` / `claudemddocker` — symlinks CLAUDE.md for Docker projects

## Omarchy (Arch Desktop Shell)

- **Shell config:** `~/.config/omarchy/shell.json` (bar layout), `shell.toml` (sizing/theme)
- **Custom plugins:** `~/.config/omarchy/plugins/ecloaiza.*` — tray, pomodoro, proton-drive, zone, blueiris
- **Plugin sync:** bidirectional rsync between tars and case
- **Plugin edits:** require full shell restart (`killall quickshell`)
- **Bar toggle:** `~/.local/state/omarchy/toggles/bar-off` hides bar (persists across reboots)
