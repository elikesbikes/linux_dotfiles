---
revision: 3
updated: 2026-11-09
---

# hermes-vault

Lets the Hermes agent on endurance (Open WebUI / Discord / dashboard) **create** school notes in the Obsidian vault and **read** the owner's homelab docs, and nothing more. Sibling of [hermes-diag](../hermes-diag/README.md): same idea (an SSH account whose only program is a strict gate), but for writing notes instead of reading diagnostics.

## Table of Contents

1. [How it fits together](#1-how-it-fits-together)
2. [What the gate allows](#2-what-the-gate-allows)
3. [Secrets](#3-secrets)
4. [Install, test, remove](#4-install-test-remove)
5. [Known limits](#5-known-limits)
6. [Revision History](#6-revision-history)

## 1. How it fits together

chattars (Open WebUI) -> Hermes on endurance -> skill `school-notes` (`hvault create <path>`, note text on stdin) or skill `homelab-notes` (`hvault list|get <path>`) -> SSH as `hermes-vault@hailmary` (key pinned to endurance's address) -> forced command `vaultgate.py` -> MCC's `vault_fetch` module -> CouchDB -> LiveSync -> the owner's Obsidian.

## 2. What the gate allows

| Verb | Where | Notes |
|---|---|---|
| `help` | - | no secrets loaded |
| `list <prefix>` | `Career/Courses/`, `Templates/`, `IT/github/adastra/Homelab/` | note paths |
| `get <path.md>` | `Career/Courses/`, `Templates/`, `IT/github/adastra/Homelab/` | one note's text (max 512 KiB returned) |
| `create <path.md>` | `Career/Courses/<existing course>/` only | text on stdin, max 256 KiB, UTF-8; **refused if the note exists** (case-insensitive) |

Never: overwrite, delete, rename, write outside `Career/Courses/` (so the Homelab docs are **read-only**), invent a new course folder, go deeper than `Career/Courses/<course>/<folder>/<note>.md` (5 parts). Homelab paths may be up to 12 parts deep (its deepest note had 10 on 2026-11-09; all 296 notes passed the path rules).

Why Homelab is readable (owner, 2026-11-09): Hermes on endurance could not see the homelab docs when asked to review them. Anyone who can chat with this Hermes can now ask for them, including IPs and the Findings Backlog; the owner accepted that. The docs hold no secrets (those live in Proton Pass). Paths are checked before any secret is loaded (tests: `test_vaultgate.py`). Every request goes to syslog (tag `hermes-vault`, Graylog); writes also produce MCC's `vault.write` audit event.

## 3. Secrets

- Its **own** Proton Pass PAT `hailmary-hermes-vault` (owner's rule: one PAT per host and user), granted **Viewer on three items only**: `MCC - COUCHDB_USER`, `MCC - COUCHDB_PASSWORD`, `MCC - VAULT_PASSPHRASE`. Expires 2027-10-29 (renew: `pass-cli personal-access-token renew`). Item-only grants mean the PAT sees **no vault**: each item is its own share, so the gate finds the share id by title (`share list --only-items true --output json`) and reads with `item view --share-id` (`--vault-name HOMELAB` fails with "Could not find vault").
- Sealed in the TPM at handle **0x81010002**. The account is **not** in `tss`; it reaches the TPM only through `unseal-pat` via one exact sudo rule with no arguments (`sudoers/sudoers.d/60-hermes-vault`). Why: the owner's PAT at `0x81010001` is sealed without an auth value, so any `tss` member could unseal it. `install.sh` proves the account cannot.
- The pass-cli session is kept in `~hermes-vault/.pp-session` (mode 700) so a note does not cost a Proton login (Proton rate-limits logins). Compromise runbook: delete that folder, revoke the PAT, rotate the three items.
- SSH key: the same Hermes container key hermes-diag trusts (both accounts are used by the same container, so a second key would not reduce exposure).

## 4. Install, test, remove

```bash
# on hailmary, from the dotfiles checkout (asks for the PAT token, hidden)
sudo ~/scripts/hermes-vault/install.sh
# tests (anywhere)
uvx pytest -q ~/scripts/hermes-vault/test_vaultgate.py
# update only the gate program after a change reached hailmary (keeps the old one as vaultgate.py.prev)
sudo ~/scripts/hermes-vault/update-gate.sh
# remove
sudo ~/scripts/hermes-vault/uninstall.sh
```

`install.sh` validates everything first, checks the sshd drop-in does not change other users' settings before reloading sshd, and ends with a real `list` through Proton and CouchDB.

## 5. Known limits

- Each call downloads the vault index (about 10 s); a `create` does two (exists check + write).
- The gate imports MCC's live `tools/vault_fetch.py`, so it always writes the current LiveSync format; an MCC refactor of `list_notes`/`get_note`/`put_note` would break it (it fails closed with `FAILED:`).
- `pass-cli` is a pinned copy in `/usr/local/lib/hermes-vault/`; re-run `install.sh` (after `sudo tpm2_evictcontrol -C o -c 0x81010002`) to update it.

## 6. Revision History

| Rev | Date | Commit | Change |
|---|---|---|---|
| 1 | 2026-10-28 | 3fb6d1d | Initial gate: create-only school notes, own TPM-sealed per-item PAT. |
| 2 | 2026-10-28 20:49 | 847277c | Read secrets by item share id (item-scoped PAT sees no vault); 38 tests. |
| 3 | 2026-11-09 | (this revision) | v1.13.0. Read-only access to `IT/github/adastra/Homelab/` (up to 12 parts deep) for the new `homelab-notes` skill; `update-gate.sh` updates only the gate program; 51 tests. |
