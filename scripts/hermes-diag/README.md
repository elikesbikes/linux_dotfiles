---
revision: 1
updated: 2026-10-02 15:10
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
| sudo | `/etc/sudoers.d/60-hermes-diag` | the account may run only four EXACT commands (no wildcards) as root: `docker logs --tail 200 <container>` and `journalctl -u mcc-runner.service …` |
| Account | `hermes-diag` | not in `docker`, `sudo`, `adm` or `systemd-journal`; no password |

## 2. What Hermes can ask

| Request | Result |
|---|---|
| `status` | MCC components that are not ok (from MCC's local API) |
| `component <name>` | full state of one component |
| `container-logs <name>` | last 200 lines of `tars-mcc-bot`, `case-mcc-bot` or `tars-n8n` |
| `service-journal <unit>` | last 200 journal lines of `mcc-runner.service` |
| `help` | this list |

The allowlists live in `diag.py` (`CONTAINERS`, `UNITS`); `install.sh` generates the sudoers rules from the same file, so they cannot drift apart. Output is sent to the AI provider as part of the conversation, which is why secret-looking text is redacted first. Redaction is pattern-based and cannot be perfect.

## 3. Install and remove

On the target host, as a user who can use `sudo`:

    sudo scripts/hermes-diag/install.sh /path/to/hermes-diag.pub [allowed-source-ip]
    sudo scripts/hermes-diag/uninstall.sh

`install.sh` validates the key, the sudoers rules (`visudo -cf`) and the sshd config (`sshd -t`, then `sshd -T -C user=hermes-diag…` to confirm the settings are really in effect) before it reloads sshd, and removes its sshd drop-in again if the checks fail. The sudoers drop-in is host-local: `.unison/sudoers.prf` ignores `60-hermes-diag` so the sudoers sync never copies it into the repo or to other hosts.

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

75 tests cover hostile requests, each validation layer on its own, exact commands, redaction, the output cap and the audit log. The gate was also mutation-tested (each protection deliberately broken in a copy and the tests required to fail).

## 7. Revision History

| Rev | Date | Commit | Change |
|---|---|---|---|
| 1 | 2026-10-02 15:10 | (this revision) | Initial version: gate, installer, uninstaller, tests. |
