# Proton Pass Secret Injection for Homelab

## Overview

This approach eliminates plaintext secrets from disk by using the Proton Pass CLI
(`pass-cli`) to resolve secrets at runtime. Secrets are stored in the **HOMELAB**
vault in Proton Pass and injected into Docker containers via environment variables
— they only ever exist in memory, never as files.

## How It Works

There are two injection methods, depending on whether the service uses a PAT
(Personal Access Token) for unattended startup or a manual `pass-cli login`.

### Method 1: PAT + `start.sh` (preferred — fully unattended)

1. Secrets are stored in the **HOMELAB** vault in Proton Pass
2. `.env` files hold only non-secret config (no `pass://` URIs)
3. A `start.sh` script authenticates with a PAT, fetches each secret via
   `pass-cli item view`, exports them as env vars, and runs `docker compose`
4. The container receives the actual secret — it never touches disk
5. No human login needed — works from systemd, cron, or after reboot

```bash
# Start the service (no manual login required)
~/devops/docker/<service>/start.sh
```

### Method 2: `pass-cli run` with `pass://` URIs (legacy — requires manual login)

1. `.env` files contain `pass://` URIs instead of plaintext values
2. `pass-cli run` resolves the URIs and passes the real values to `docker compose`
3. Requires a manual `pass-cli login` after every reboot

```bash
pass-cli run --env-file ~/devops/docker/<service>/.env -- \
  docker compose -f ~/devops/docker/<service>/docker-compose.yml up -d
```

```
pass://HOMELAB/<item-title>/<field>
         │          │          │
         │          │          └─ "note" for note items, "password" for logins
         │          └─ exact item title in Proton Pass
         └─ vault name
```

## Requirements

- Proton Pass paid plan (Pass Plus or Proton Unlimited)
- `pass-cli` installed at `~/.local/bin/pass-cli`
- **Method 1 (PAT):** PAT stored at `~/.secrets/proton-pass-pat` (mode 600)
- **Method 2 (legacy):** Active session via `pass-cli login` (required after reboot)

## PAT Setup

The Personal Access Token allows `pass-cli` to authenticate without human
interaction. It has **Viewer** access to the HOMELAB vault (read-only).

- Generated in: Proton Pass → Settings → Security → Personal Access Tokens
- Stored at: `~/.secrets/proton-pass-pat` (mode 600, owner-readable only)
- Revoke instantly from Proton Pass settings if compromised

## Currently Migrated

| Service   | Secrets                                                          | Method    | Status |
|-----------|------------------------------------------------------------------|-----------|--------|
| Traefik   | CF_DNS_API_TOKEN                                                 | PAT start.sh | Done |
| Authelia  | JWT_SECRET, SESSION_SECRET, STORAGE_ENCRYPTION_KEY, SMTP_PASSWORD | PAT start.sh | Done |
| Graylog   | GRAYLOG_ROOT_PASSWORD_SHA2, GRAYLOG_PASSWORD_SECRET              | PAT start.sh | Done |
| GitLab    | GITLAB_TOKEN (API + git credential)                              | PAT credential helper + shell | Done |
| UniFi     | UNIFI_PASSWORD, UNIFI_API_KEY, SSH key                           | PAT shell + SSH agent | Done |
| Home Assistant | HASS_TOKEN                                                  | PAT shell | Done |
| Uptime Kuma | UPTIME_KUMA_PASSWORD                                           | PAT shell | Done |
| Certbot   | deploy_to_unifi.sh (SSH key)                                     | SSH agent | Done |
| Ansible   | MYSQL_PASSWORD, SEMAPHORE_ADMIN_PASSWORD, SEMAPHORE_ACCESS_KEY_ENCRYPTION | PAT start.sh | Done |
| n8n       | UNIFI_PASS, GRAYLOG_API_TOKEN, HA_TOKEN, UPTIME_KUMA_PASSWORD, N8N_ENCRYPTION_KEY, N8N_BASIC_AUTH_PASSWORD, GARMIN | PAT start.sh | Done |
| Restic    | RESTIC_PASSWORD                                                  | PAT start.sh | Done |

## Candidates for Migration

| Service    | Secrets in .env                                                  |
|------------|------------------------------------------------------------------|
| CouchDB    | DB_PASSWORD                                                      |
| Joplin     | POSTGRES_PASSWORD                                                |
| ~~Ansible~~  | ~~MYSQL_PASSWORD, SEMAPHORE_ADMIN_PASSWORD, SEMAPHORE_ACCESS_KEY_ENCRYPTION~~ → migrated |
| Reviere    | ANTHROPIC_API_KEY                                                |
| Nextcloud  | DB_PASSWORD, DB_ROOT_PASSWORD                                    |

## Other Use Cases

### SSH Keys
SSH keys are stored in the HOMELAB vault and served by the Proton Pass SSH agent.
No plaintext private keys on disk — `~/.secrets/ssh/` directory removed. The systemd
service (`proton-pass-ssh-agent.service`) starts the agent with PAT auto-login.
Keys loaded: `tars SSH Key - ed25519`, `UniFi Router SSH Key - RSA`.
Claude skills (`unifi`, `unifi-dns`) use the agent socket instead of key files.

### Git Credentials (GitHub + GitLab HTTPS)
A credential helper script at `~/scripts/proton-pass/git-credential-protonpass`
handles both `github.com` and `gitlab.home.elikesbikes.com`, pulling tokens from
the HOMELAB vault via PAT. No `.git-credentials` file on disk.

### GitLab API Token
`~/.secrets/gitlab` fetches `GITLAB_TOKEN` from Proton Pass on shell startup
(sourced by `.bashrc`). Used by shell functions for GitLab API calls.
No plaintext token on disk.

## Production Migration

These same services will be migrated on the **prod host (endurance)** using the
identical `start.sh` pattern. Steps:
1. Create a PAT for endurance in Proton Pass (name: "ENDURANCE")
2. Store at `~/.secrets/proton-pass-pat` on endurance
3. Copy `start.sh` scripts (they're host-agnostic — all paths are relative)
4. Update `env.sample` / `.env` with prod-specific values (hostnames, syslog targets)

## Adding a New Service (PAT method)

1. Create items in the HOMELAB vault:
   ```bash
   PROTON_PASS_AGENT_REASON="Creating secret for <service>" \
     pass-cli item create note --vault-name HOMELAB \
     --title "<service> - <SECRET_NAME>" --note "<value>"
   ```

2. Create a `start.sh` in the service directory (see `graylog/start.sh` as a
   template). The script should:
   - Authenticate with the PAT from `~/.secrets/proton-pass-pat`
   - Fetch each secret with `pass-cli item view` and a reason
   - Export secrets as env vars
   - Source non-secret vars from `.env`
   - Run `docker compose up -d`

3. Remove plaintext secrets from `.env` and replace with comments noting
   which Proton Pass item holds the value.

4. Start with:
   ```bash
   ~/devops/docker/<service>/start.sh
   ```

## Gotchas

- **PAT sessions are isolated** — each `start.sh` uses its own session dir
  (`/tmp/pass-agent-<service>`) to avoid conflicts between services.
- **PAT has Viewer role** — it can read secrets but cannot create/modify them.
  Use your personal login for `item create` / `item update`.
- **`pass-cli run` does NOT work with PAT sessions** — agent sessions require
  `PROTON_PASS_AGENT_REASON` per command, which `run` can't provide. Use
  `item view` instead.
- **Item titles must match exactly** — including spaces and punctuation.
- **Note items use `note` field, login items use `password`** — pick the right
  field for your item type.
