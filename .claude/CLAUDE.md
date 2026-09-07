# Global Rules

## Identity

Always operate as user `ecloaiza` on all systems (GitLab, SSH, APIs). Never use `root`. When creating PATs, registering runners, or performing API operations, target `ecloaiza` — never `root`.

## Research Before Assertions

Do not assume how software behaves. Verify claims with source code, documentation, or testing before stating them as fact. If you cannot verify, say "I'm not sure" rather than stating it confidently. This is especially important when the assumption would drive architectural decisions.

## Git — No Manual Commands

Never run `git add`, `git commit`, `git push`, or any manual git commands. Claude Code hooks handle commits and pushes automatically after file edits. For manual triggers, use the `gacp_*` shell functions:

- `gacp_adastra "message"` — commit + push adastra repo + sync to Obsidian
- `gacp_dotfiles "message"` — commit + push linux_dotfiles repo

## Pipeline Workflow

Standard CI/CD flow for all projects:

- **Docker/web:** tars (edit) → rocky (dev, auto-deploy) → hailmary (prod, manual deploy)
- **iOS/Xcode:** tars (edit) → kipp (macOS build/test)

## Active Hosts

Only four hosts are live: **tars** (desktop/sandbox), **rocky** (dev), **hailmary** (prod), **kipp** (macOS/iOS).

Retired hostnames: `endurance`, `ranger0`, `ranger1`, `docker-prod-1/2/3`, `gargantua`, `case`. A live machine may reuse a retired hostname — do not assume a successful SSH means the original host is still in service. If a doc or skill references a retired host, treat it as stale.

## Network Infrastructure

- **UniFi Router** — 192.168.5.1, SSH via RSA key in Proton Pass HOMELAB vault
- **Domain** — `home.elikesbikes.com` (internal DNS via UniFi)
- **GitLab** — `gitlab.home.elikesbikes.com` (self-hosted, user: ecloaiza)
- **GitHub** — user: elikesbikes

## Environment Tiers

| Tier | Host | Traefik Dashboard | Authelia | Purpose |
|------|------|-------------------|----------|---------|
| **Production** | hailmary | proxy-hailmary.home.elikesbikes.com | auth-hailmary.home.elikesbikes.com | Prod services, external-facing proxied hosts |
| **Development** | rocky | proxy-rocky.home.elikesbikes.com | auth-rocky.home.elikesbikes.com | Service development and testing |
| **Sandbox** | tars | — | — | Experimental Docker work, throwaway setups |

## Directory Layout

| Path | Purpose |
|------|---------|
| `~/devops/` | Main development workspace |
| `~/devops/docker/` | All Docker project directories (n8n, traefik, authelia, graylog, ansible, restic, etc.) |
| `~/devops/github/adastra/` | Homelab documentation repo (GitLab only) |
| `~/devops/github/linux_dotfiles/` | Dotfiles repo (GitHub + GitLab) |
| `~/devops/projects/` | Standalone project directories (domain-search, missioncontrol, reviere, etc.) |
| `~/scripts/<topic>/` | Custom scripts (certbot, proton-pass, etc.) |
| `~/.secrets/` | Secrets only (PAT, cloudflare.ini, etc.) |
| `~/.claude/skills` | Symlink → `~/devops/github/adastra/AI/skills/` |

## MCP Servers (Claude Code)

Registered in `~/.claude/settings.json` — check there for the current list and connection details.

## Obsidian Vault

- **Path:** `~/Documents/Obsidian/Loaiza/` — NEVER read or write locally
- **All access via CouchDB on hailmary:** `ssh hailmary "cd /home/ecloaiza/devops/projects/mcc && python3 tools/vault_fetch.py --get|--put|--list '<path>'"`
- **Sync:** Self-hosted LiveSync via CouchDB on hailmary
- **Homelab views:** `IT/github/adastra/Homelab/` — IPAM, services, projects, infra databases

## Security / Secrets Management

### Proton Pass

- **Full documentation:** Obsidian vault at `IT/github/adastra/Homelab/Proton Pass Secrets.md`
- **Per-service status:** `secrets_management` field in each service doc at `IT/github/adastra/Homelab/services/`
- **Vaults:** Emmanuel Vault (personal), Family, Escuincles, Career, HOMELAB
- **SSH Agent:** systemd service, 7 keys in HOMELAB vault, socket at `~/.ssh/proton-pass-agent.sock`
- **PAT:** stored at `~/.secrets/proton-pass-pat` (or TPM-sealed at handle `0x81010001`)
- **Git credentials:** `~/scripts/proton-pass/git-credential-protonpass` handles github.com + gitlab.home.elikesbikes.com
- **Docker secrets:** `start.sh` per service — PAT login → `pass-cli item view` → export → docker compose

**Rule:** When migrating a service to Proton Pass, update BOTH:
1. The service's doc in the vault (`secrets_management` field) — this is the source of truth for what uses what
2. The Proton Pass Secrets doc in the vault (`IT/github/adastra/Homelab/Proton Pass Secrets.md`) — if the process/gotchas change

### TPM-Sealed PAT

All hosts use TPM handle `0x81010001` to seal the Proton Pass PAT.

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
