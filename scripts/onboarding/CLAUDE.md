# CLAUDE.md — Linux Dotfiles Onboarding

Guidance for working in this project (`scripts/onboarding`). These rules describe the
conventions every script here follows. Match them when editing or adding scripts.

## What this project is

An idempotent onboarding system for fresh Debian/Ubuntu GNOME hosts. A `gum` menu
(`scripts/master/master.sh`) orchestrates per-category `install_*.sh` scripts that
install software and deploy dotfiles via GNU Stow. See `README.md` for the overview.

## Layout

- `scripts/<category>/install_*.sh` — installers, **auto-discovered** by the master menu
- `scripts/verify/verify_<category>.sh` — audit-only checks (extensions verifies itself)
- One `README.md` per directory describing that category

Categories: `core`, `cli`, `desktop`, `security`, `extensions`, `themes`, `dotfiles`.

## Hard rules

1. **Idempotent always.** Every `install_*.sh` must be safe to re-run. Check the state
   marker first, then the installed binary/package, before doing any work.
2. **State markers.** On success, `touch "$STATE_DIR/<tool>"` where
   `STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"`.
   Use the real tool name — never a literal placeholder like `<category>`.
   The marker `touch` must run on the actual success path, not after an `exit`.
3. **Only `core` runs `apt update`.** Other categories call `apt-get install` directly
   and assume the cache is fresh. (Standalone scripts that add a repo may refresh.)
4. **Official sources only.** Add third-party repos explicitly with modern signed-by
   GPG keyrings under `/etc/apt/keyrings`. No piping unknown scripts as root.
5. **`gum` is UX only.** Never hide execution behind menu choices.
6. **Configuration via dotfiles/Stow**, not installers. Installers install software;
   they do not write user config.
7. **Logs.** Write to `${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/logs/<script>.log`,
   typically via `exec > >(tee -a "$LOG_FILE") 2>&1`.

## Script conventions

- Start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Derive `SCRIPT_NAME="$(basename "$0")"` — do not hardcode the filename (it drifts on
  copy/paste; a past bug had `install_fastfetch.sh` installing neovim).
- Header comment block with `Version:` and a short changelog for non-trivial scripts.
- Validate after install (`command -v` or `dpkg -s`) and exit non-zero on failure.
- Quote variables; honor `XDG_STATE_HOME`.

## Bash gotchas (enforced here)

- Do **not** use `((VAR++))` under `set -e` — it returns non-zero when `VAR` was 0 and
  aborts the script. Use `VAR=$((VAR+1))`.
- Verify scripts use `set -uo pipefail` (no `-e`) so a single failing check is counted,
  not fatal; they `exit` with the count of failures.
- Put marker `touch` and state writes before any early `exit 0`.

## Adding a tool

1. Drop `install_<tool>.sh` in the right category (copy `cli/install_zoxide.sh` as the
   reference template — clean state-marker pattern).
2. Add a row to that category's `README.md`.
3. Add a check to the matching `verify/verify_<category>.sh`.
4. The master menu picks it up automatically (no registration needed).

## Verifying changes

- `bash -n <script>` for syntax on every script you touch.
- Run the relevant `verify/verify_<category>.sh`.
- Do not actually run installers in CI/agent contexts (they need `sudo`, network, and a
  real host); rely on syntax + verify scripts instead.

## Committing

The user commits with the `gacp_dotfiles "message"` shell function, which does
`git add . && commit && pull --rebase && push` to `main` (GitHub + GitLab remotes).

**This working tree is auto-reset to `origin/main`** (the reflog shows recurring
`reset: moving to origin/main`). Any change that is only saved to disk — but not
committed AND pushed — is silently wiped on the next sync. This has repeatedly
destroyed uncommitted README edits.

Rules:
- **Edit → commit immediately.** Never leave edits (code OR docs) sitting
  uncommitted across steps. Bundle the `gacp_dotfiles` commit in the same turn.
- Only committed+pushed work survives; a clean `git status` after edits means the
  edits are gone, not saved.
- After committing, confirm the push hit **both** GitHub and GitLab.
