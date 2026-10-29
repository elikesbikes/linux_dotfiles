---
revision: 2
updated: 2026-10-28
---

# hermes-vault

Lets the Hermes agent (chattars / Discord) **create** school notes in the Obsidian vault, and nothing more. Sibling of [hermes-diag](../hermes-diag/README.md): same idea (an SSH account whose only program is a strict gate), but for writing notes instead of reading diagnostics.

## Table of Contents

1. [How it fits together](#1-how-it-fits-together)
2. [What the gate allows](#2-what-the-gate-allows)
3. [Secrets](#3-secrets)
4. [Install, test, remove](#4-install-test-remove)
5. [Known limits](#5-known-limits)
6. [Revision History](#6-revision-history)

## 1. How it fits together

chattars (Open WebUI) -> Hermes on endurance -> skill `school-notes` -> `hvault create <path>` (note text on stdin) -> SSH as `hermes-vault@hailmary` (key pinned to endurance's address) -> forced command `vaultgate.py` -> MCC's `vault_fetch` module -> CouchDB -> LiveSync -> the owner's Obsidian.

## 2. What the gate allows

| Verb | Where | Notes |
|---|---|---|
| `help` | - | no secrets loaded |
| `list <prefix>` | `Career/Courses/`, `Templates/` | note paths |
| `get <path.md>` | `Career/Courses/`, `Templates/` | one note's text |
| `create <path.md>` | `Career/Courses/<existing course>/` only | text on stdin, max 256 KiB, UTF-8; **refused if the note exists** (case-insensitive) |

Never: overwrite, delete, rename, write outside `Career/Courses/`, invent a new course folder, go deeper than `Career/Courses/<course>/<folder>/<note>.md`. Paths are checked before any secret is loaded (tests: `test_vaultgate.py`). Every request goes to syslog (tag `hermes-vault`, Graylog); writes also produce MCC's `vault.write` audit event.

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
| 2 | 2026-10-28 | (this revision) | Read secrets by item share id (item-scoped PAT sees no vault); 38 tests. |
