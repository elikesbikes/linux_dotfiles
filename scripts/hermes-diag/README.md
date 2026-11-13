---
revision: 8
updated: 2026-11-12 20:03
---

# hermes-diag: read-only diagnostics for the Hermes agent

Lets the Hermes agent (on endurance) look at a host's MCC status, MCC container logs and the MCC runner journal over SSH, **read-only**, so it can help diagnose problems. Installed per host (first on hailmary). Fixes are deliberately not possible through this account.

## Table of Contents

1. [How the restrictions are enforced](#1-how-the-restrictions-are-enforced)
2. [What Hermes can ask](#2-what-hermes-can-ask)
3. [Install and remove](#3-install-and-remove)
4. [Traceability and logging](#4-traceability-and-logging)
5. [Known limits](#5-known-limits)
6. [Tests](#6-tests)
7. [Revision History](#7-revision-history)

## 1. How the restrictions are enforced

Hermes is an AI agent, so nothing here depends on it behaving. Enforcement is on the host:

| Layer | Where | What it does |
|---|---|---|
| Source pin and key restrictions | `/etc/ssh/hermes-diag.authorized_keys` (root-owned) | `from="<endurance ip>",restrict,command=…`: one key, one source address, no tty, no forwarding |
| sshd `Match User hermes-diag` | `/etc/ssh/sshd_config.d/60-hermes-diag.conf` | `ForceCommand` to the gate, public key only, no tty or forwarding, root-owned key file |
| The gate | `/usr/local/lib/hermes-diag/diag.py` (root-owned) | allowlisted subcommands, exact-match arguments, no shell, secrets redacted, output capped, every request logged |
| sudo | `/etc/sudoers.d/60-hermes-diag`, from `sudoers/sudoers.d/60-hermes-diag` in this repo | the account may run only four EXACT commands (no wildcards) as root: `docker logs --tail 200 <container>` and `journalctl -u mcc-runner.service …`. The rule names the host (`hermes-diag hailmary=…`), so it does nothing on any other machine |
| Account | `hermes-diag` | not in `docker`, `sudo`, `adm`, `systemd-journal` or `tss`; no password |
| Its own MCC key (hailmary) | TPM handle `0x81010003`, `/usr/local/lib/hermes-diag/{unseal-pat,pass-cli}`, `~hermes-diag/.pp-session` | see section 3a |

## 2. What Hermes can ask

The same `diag.py` runs on every target; the host's profile (by short hostname) and OS decide what it offers. **Generic, no privileges, every host:** `hostinfo`, `os`, `disk`, `memory`, `load`, `processes` (names only), `network`; **Linux only:** `listening`, `failed-units`. macOS output drops serial numbers/hardware UUID. Python 3.9 compatible (macOS). Hermes calls them as `hdiag <host> <command>`. The hailmary-only MCC commands:

| Request | Result |
|---|---|
| `status` | MCC components that are not ok (from MCC's local API) |
| `component <name>` | full state of one component |
| `container-logs <name>` | last 200 lines of `tesseract-mcc-bot`, `lazarus-mcc-bot` or `mcc-n8n` |
| `service-journal <unit>` | last 200 journal lines of `mcc-runner.service` |
| `fit <name> [n]` | hailmary only: the owner's fitness, health and lab data. Each of 36 names maps to ONE fixed GET on MCC's local `http://127.0.0.1:5679/api/life/...` (data files only; no Garmin call, no writes); `n` = a capped day/week/month count or, for `activity-compare`, a numeric activity id. `rides`/`activities` come as a compact table and `labs` without the point history, so they fit the 64 KB cap. Owner approved 2026-10-29, including anxiety and labs |
| `help` | this list |

The allowlists live in `diag.py` (`CONTAINERS`, `UNITS`); `install.sh` generates the sudoers rules from the same file, so they cannot drift apart. Output is sent to the AI provider as part of the conversation, which is why secret-looking text is redacted first. Redaction is pattern-based and cannot be perfect.

## 3. Install and remove

**macOS (kipp):** `sudo ./install-macos.sh <pubkey> [source-ip]` and `sudo ./uninstall-macos.sh`. It makes a hidden standard user with `dscl`, adds it to `com.apple.access_ssh` (macOS only allows SSH for that group; here the nested `admin` group), installs the sshd drop-in and checks other users' sshd settings are unchanged. No sudoers there. Linux instructions follow.

On the target host, as a user who can use `sudo`:

    sudo scripts/hermes-diag/install.sh /path/to/hermes-diag.pub [allowed-source-ip]
    sudo scripts/hermes-diag/uninstall.sh

The sudoers rule is **not** written by hand: `gen-sudoers.py` generates it from the allowlists in `diag.py`, the result is committed as `sudoers/sudoers.d/60-hermes-diag`, and the dotfiles pipeline deploys it to rocky and hailmary (`sync-sudoers-ci.sh`). After changing an allowlist run `python3 scripts/hermes-diag/gen-sudoers.py --write sudoers/sudoers.d/60-hermes-diag` and commit it **as the newest commit of the push**: the CI step only checks whether the last commit touched `sudoers/`. `install.sh` refuses to run if the repo file is out of date with `diag.py`.

`install.sh` validates the key, the sudoers rules (`visudo -cf`) and the sshd config (`sshd -t`, then `sshd -T -C user=hermes-diag…` to confirm the settings are really in effect) before it reloads sshd, and removes its sshd drop-in again if the checks fail. The pipeline reaches only rocky and hailmary (tars and endurance do not run it).

### 3a. The account's own MCC key (hailmary, since 2026-11-12)

Since MCC security audit run 4 the MCC runner wants a key from every local caller, so `status`, `component` and `fit` get **401** without one. The account has its **own** read-only key, `MCC - MCC_TOKEN_HERMES_DIAG` (MCC allows it `GET /api/status`, `/api/life/fitness/`, `/api/life/health/`, `/api/life/medical/labs`, from loopback only), and reads it with its **own** Proton Pass PAT `hailmary-hermes-diag` (owner's rule: one PAT per host and user). Same pattern as `scripts/hermes-vault`:

- The PAT is granted **Viewer on that one item only**, so it sees no vault: the gate finds the item's share id by title (`share list --only-items`) and reads its `note` field by share id.
- It is sealed in the TPM at handle **`0x81010003`**. The account is **not** in `tss`; it reaches the TPM only through the root-owned `unseal-pat` via one exact sudo rule with no arguments (generated into `sudoers/sudoers.d/60-hermes-diag`). It cannot unseal the owner's PAT (`0x81010001`) or hermes-vault's (`0x81010002`); `enable-mcc-key.sh` proves it.
- The pass-cli session is kept in `~hermes-diag/.pp-session` (mode 700), so a call does not cost a Proton login (Proton rate-limits logins); the PAT is unsealed and used only when that session is gone. The key lives only in the gate's process and is sent as `Authorization: Bearer` to `127.0.0.1:5679`; it is never printed.
- Errors say what is wrong without a secret: `hermes-diag: MCC key: <reason>` (no key set up on this host, TPM read failed, Proton login failed or rate-limited, item not readable, runner refused with HTTP 401/403).

Set it up once on hailmary (after the dotfiles pipeline has put this version there):

1. In Proton Pass, create a personal access token named `hailmary-hermes-diag` and copy it. The app can grant a token only whole vaults, so give it access to **one item** with `pass-cli` from your **own** login (a token session gets `NotAllowed`), in a temporary session folder so the host's own session stays:

       export PROTON_PASS_SESSION_DIR="$(mktemp -d)" PROTON_PASS_KEY_PROVIDER=fs
       pass-cli login                                   # web login, your account
       pass-cli personal-access-token access list-access --personal-access-token-name hailmary-hermes-diag
       # if it lists a Type=Vault grant, revoke it FIRST (an item grant inside a granted vault is NotAllowed):
       pass-cli personal-access-token access revoke --personal-access-token-name hailmary-hermes-diag --share-id <vault grant id>
       pass-cli personal-access-token access grant --personal-access-token-name hailmary-hermes-diag \
         --vault-name HOMELAB --item-title "MCC - MCC_TOKEN_HERMES_DIAG" --role viewer
       pass-cli logout --force; rm -rf "$PROTON_PASS_SESSION_DIR"

   `list-access` must then show exactly one line, `MCC - MCC_TOKEN_HERMES_DIAG | Type=Item | Role=Viewer`.
2. On hailmary: `sudo ~/devops/github/linux_dotfiles/scripts/hermes-diag/enable-mcc-key.sh` and paste the token when asked (hidden). It installs the current `diag.py` (the old one is kept as `diag.py.prev`), the helper and a pinned `pass-cli`, installs the repo sudoers file, seals the PAT, checks isolation, and ends with a real `status` and `fit readiness` as the account.

Live on hailmary since 2026-11-12, verified from the Hermes container (`hdiag hailmary status`, `fit readiness`, `container-logs mcc-n8n`).

Compromise runbook: delete `~hermes-diag/.pp-session`, revoke the PAT, rotate `MCC - MCC_TOKEN_HERMES_DIAG` (MCC reloads it on its next start). Undo: see the top of `enable-mcc-key.sh`.

## 4. Traceability and logging

- Every request, accepted or rejected, is written to syslog as `hermes-diag` with the client address, outcome, size, time and the (escaped) request text. Syslog ships to Graylog.
- sshd logs the key fingerprint for each login. sudo logs each command to `/var/log/sudo-hermes-diag.log`.
- The key is Hermes' own (never shared) and is named `endurance hermes-diag` in Proton Pass.

## 5. Known limits

- The gate can only be as good as its allowlists and patterns; a bug there is the main risk, which is why the tests try to break it.
- Redaction is pattern-based. Review what a log can contain before adding a container to the allowlist.
- Read-only means Hermes can explain a failure but cannot fix it. Fix actions are a later, separate decision.

## 6. Tests

    python3 -m pytest scripts/hermes-diag/test_diag.py

The tests cover hostile requests, each validation layer on its own, exact commands, redaction, the output cap, the audit log and the committed sudoers file (no drift from the allowlists, no wildcards, host-restricted), and the own-key path: the kept session is used without a login, one login with the sealed PAT (passed in the environment, never argv) when it is gone, every failure says why without a secret, the runner call carries the key, a refused key is reported plainly, the unseal rule is one exact command and the helper names only `0x81010003`. A test that replaces `_api_fetch` really does now (before 2026-11-12 the `main()` test reached the live runner on the build host). The gate was also mutation-tested (each protection deliberately broken in a copy and the tests required to fail).

## 7. Revision History

| Rev | Date | Commit | Change |
|---|---|---|---|
| 8 | 2026-11-12 20:03 | v1.16.2 | Setup step 1: item-only grant through `pass-cli` (the app grants only vaults; revoke a vault grant first); live on hailmary, verified from Hermes. |
| 7 | 2026-11-12 19:20 | v1.16.1 | Session folder from the account's own home (not `$HOME`); self-test with `sudo -H`. 144 tests. |
| 6 | 2026-11-12 19:19 | v1.16.0 | Own MCC key (run 4): `enable-mcc-key.sh`, `unseal-pat` (TPM `0x81010003`), Bearer key on the runner calls, unseal sudo rule; fetch functions looked up at call time (a test reached the live runner); hailmary's installed gate still had the pre-rename container names (fixed by the next `enable-mcc-key.sh`). 143 tests. |
| 5 | 2026-11-09 13:20 | (this revision) | MCC containers renamed with the trust zones (TARS/CASE to TESSERACT/LAZARUS): `tesseract-mcc-bot`, `lazarus-mcc-bot`, `mcc-n8n` in the hailmary allowlist and the generated sudoers rule. |
| 4 | 2026-10-29 | 308d601 | `fit` group: 36 read-only fitness/health/labs views from MCC's local API, hailmary only (129 tests). |
| 3 | 2026-10-02 17:30 | (see git) | Multi-host: generic commands, Linux/macOS profiles, macOS installer (93 tests). |
| 2 | 2026-10-02 16:05 | (see git) | Sudoers rule moved into the repo (generated, host-restricted, deployed by the pipeline); drift tests. |
| 1 | 2026-10-02 15:10 | 5d8636d | Initial version: gate, installer, uninstaller, tests. |
