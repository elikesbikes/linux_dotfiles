---
revision: 1
updated: 2026-11-08 10:45
---

# hermes-secrets (Hermes key helper)

Author: TARS (Emmanuel Loaiza)

## 1. What it is

`hermes-secrets.sh` gives a full Hermes install on a workstation (case, later tars) its keys **without any key file on disk**. Hermes v0.23 can run a helper command at start and read `KEY=VALUE` lines from it (the built-in `command` secret source, `secrets.command` in `~/.hermes/config.yaml`). This helper fetches the values from Proton Pass with the host's own PAT, sealed in its TPM, through `pp_load` (`scripts/proton-pass/pass-secrets.sh`).

Today it supplies one value:

| Variable | Proton item (HOMELAB) | Used by |
|---|---|---|
| `HONCHO_API_KEY` | `honcho - API key - <host>` (password field) | Hermes' Honcho memory plugin, for the shared memory on endurance (workspace `hermes`) |

Each host has its own item, so each host has its own key.

## 2. How it is wired

In `~/.hermes/config.yaml` on the host:

```yaml
secrets:
  command:
    enabled: true
    command: "$HOME/scripts/hermes-secrets/hermes-secrets.sh"
    helper_timeout_seconds: 20
```

- Hermes runs the helper once per start (desktop app backend, herdr tab, `hermes` in a terminal) and discards its stderr, so `pp_load`'s log lines and any Proton error text never reach Hermes' logs.
- `pp_load` uses a TPM-sealed cache for 10 minutes, Proton otherwise, and a cache up to 7 days old if Proton cannot be reached. A failure never blocks Hermes: it starts without the key, and memory calls get 401.
- The default helper timeout is 3 s; 20 s leaves room for a Proton login.
- Hermes' `.env` is not used for keys. `.env` and `auth.json` are never synced between hosts.

## 3. Test

```bash
~/scripts/hermes-secrets/hermes-secrets.sh 2>/dev/null | cut -d= -f1     # prints only: HONCHO_API_KEY
```

## 4. Rotation and revocation

Honcho keeps no key list. To revoke a key, rotate Honcho's JWT secret (Proton `honcho - JWT_SECRET`, see the Honcho README in the tutorials repo). That invalidates every key: endurance mints a new one at its next start, and each workstation needs a new `honcho - API key - <host>` item (delete the old one).

## Revision History

| Rev | Date | Commit | Change |
|---|---|---|---|
| 1 | 2026-11-08 10:45 | (this revision) | New: Honcho key for Hermes from Proton via `secrets.command` (first host: case). |
