# Changelog

All notable changes to this repository will be documented in this file.

This project follows a pragmatic versioning model inspired by
[Semantic Versioning](https://semver.org/).

---

## [v1.9.3] - 2026-11-08

### Changed
- `PIPELINE.md`: murph's runner now also serves adastra (adastra `.gitlab-ci.yml` gained `deploy-murph`, commit `6da0e73`).

Tested: adastra pipeline 2174 green on rocky, hailmary and murph; all three checkouts at `6da0e73` and clean.

---

## [v1.9.2] - 2026-11-08

### Changed
- murph's runner (`murph-shell`, id 12) is locked to this project and runs protected branches only. `PIPELINE.md` documents this and adds it to the new-host steps.

Tested: this push's `deploy-murph` job is the check that the locked, protected-only runner still picks up `main`.

---

## [v1.9.1] - 2026-11-08

### Fixed
- `scripts/gitlab-runner/gitlab-runner-proton.service`: stops the runner with SIGQUIT (graceful: a running job may finish, up to 5 min) instead of SIGTERM, which made the runner log "forceful shutdown" warnings. The runner config also sets `request_concurrency = 2`, which removes the "long polling issues" warning at start.

Tested: on murph, a service restart now does a graceful shutdown (no "forceful shutdown" line) and logs no long-polling warning. The runner still prints its own WARNING-level lines for any stop ("received stop signal", "Starting graceful shutdown") and for user mode ("Running in user-mode"), which rocky also logs (its runner is a user service too).

---

## [v1.9.0] - 2026-11-08

### Added
- Pipeline: `deploy-murph` job. murph (sandbox) now gets every push to `main` like rocky and hailmary, run by its own runner `murph-shell` (id 12, tags `shell,murph`).
- `scripts/gitlab-runner/gitlab-runner-proton.sh` + `.service`: a GitLab Runner for hosts that may keep no secret on disk. At start it unseals the host's TPM PAT, reads the runner token from Proton Pass (`gitlab-runner token - <host>`), writes `config.toml` to `$XDG_RUNTIME_DIR` (RAM), logs pass-cli out and starts the runner.

### Changed
- `PIPELINE.md` and README §5 rewritten to match the real pipeline (a runner on each deploy host, no SSH). The old text described an SSH deploy key and retired hosts.

Tested: CI lint valid. On murph the runner comes online with no token in any file on disk, and job 7097 passed. The first run (job 7096) had failed because `~/.bash_logout` runs `clear_console`; murph's copy now has the same interactive-only guard as rocky. The v1.9.0 push itself is the end-to-end test (see the vault note `infra/murph`).

---

## [v1.8.0] - 2026-11-08

### Added
- `scripts/hermes-secrets/hermes-secrets.sh`: helper that Hermes (v0.23+) runs at start through its `command` secret source (`secrets.command` in `~/.hermes/config.yaml`). It fetches `HONCHO_API_KEY` from Proton Pass item `honcho - API key - <host>` with the host's own TPM-sealed PAT (`pp_load`) and prints it as `KEY=VALUE` on stdout; its log lines go to stderr, which Hermes discards. No key in any file. First host: case (Hermes sync stage C3). README in the folder.

Tested on case (2026-11-08): the helper exits 0 in 1.8 s and prints one line, `HONCHO_API_KEY=` plus a 136-character value (checked by name and length only); `hermes memory status` reports `Command helper: applied 1 secret`; a one-shot chat opened a Honcho session on endurance and `honcho_search` returned shared memory; from endurance the session showed 2 messages (peers emmanuel, hermes) and was deleted. Not tested: tars (later stage), a start away from home (Proton unreachable: the 7-day cache applies; Honcho unreachable: 5 s timeout in `honcho.json`).

## [v1.7.1] - 2026-11-08

### Changed
- `.bash/aliases.sh` now holds only aliases. The functions that lived there (`claude`, `cc`, `claudepower`, `claudepowerlocal`, `codexpower`, `hermescli`) moved unchanged to `.bash/functions.sh`, under "Claude / Codex / Hermes launchers".
- `upgraderustdesk` is now a function instead of an alias. It stops with an error when apt is missing (it is for Ubuntu/Debian hosts) or when GitHub returns no .deb link. It downloads to a `mktemp` file instead of a fixed `/tmp/rustdesk.deb` and deletes the file afterwards.

Tested: shell syntax. In a clean shell, `declare -f` of the six moved functions is identical before and after, and all of them plus `upgraderustdesk` and `gpull_force` load from `~/.bashrc`. On tars, `upgraderustdesk` stops with the apt error. Not tested: a real RustDesk install on an Ubuntu host.

---

## [v1.7.0] - 2026-11-08

### Changed
- `.bash/functions.sh`: new `gpull_force` function, an easier-to-remember name next to `gpull`. It makes the current branch match origin exactly (`git fetch --all`, `git reset --hard origin/<branch>`, `git pull`), so local commits and uncommitted changes to tracked files are lost; untracked files stay. It refuses to run outside a git repo or on a detached HEAD.
- `.bash/aliases.sh`: removed the `repopullforce` alias (replaced by `gpull_force`).

Tested: shell syntax; on a throwaway repo, `gpull_force` dropped a local commit and an uncommitted edit, kept an untracked file, and refused outside a repo and on a detached HEAD.

---

## [v1.6.0] - 2026-11-08

### Added
- `scripts/proton-pass/git-credential-protonpass`: per-host git tokens, opt-in with `git config --global protonpass.hostItems true`. The helper then reads `<item> - <short hostname>` first (for example `gitlab.home.elikesbikes.com - git credential - murph`) and falls back to the shared item with a syslog warning (tag `git-credential-protonpass`) if the host item is missing. Hosts without the setting are unchanged (no extra Proton lookup). First user: murph.

Tested: shell syntax; tars unchanged (setting absent). murph: see the vault note for the GitLab push/fetch test.

---

## [v1.5.0] - 2026-11-08

### Added
- `scripts/claude/claude-proton`: starts Claude Code with the host's own `CLAUDE_CODE_OAUTH_TOKEN` from Proton Pass (item `claude - CLAUDE_CODE_OAUTH_TOKEN - <host>`, PAT from the TPM), so no Claude login is stored on disk. For no-secrets hosts such as the murph sandbox; enabled per host by linking it into `~/.local/bin`.
- `.bash/aliases.sh`: `claude()` function that uses `~/.local/bin/claude-proton` when the host has it and plain `claude` otherwise (no change on other hosts; `cc` and `claudepower` go through it too).

Tested: shell syntax; on tars `claude` still resolves to the normal binary. Not tested before release: a full murph start with the Proton token (the token item does not exist yet).

---

## [v1.4.0] - 2026-11-07

### Added
- `.hermes/plugins/herdr-app-status`: Hermes plugin that reports Hermes's turn status to herdr-app (OSC 7501) so Hermes shows in its Agents list; linked by `create-managed-symlinks.sh`.

---

## [v1.3.1] - 2026-11-07

### Fixed
- Hermes Light launcher: `--password-store=gnome-libsecret` so the sign-in token is saved in gnome-keyring on Hyprland (Electron did not detect it); desktop entry window class and category.

---

## [v1.3.0] - 2026-11-07

### Added
- `scripts/hermes-light/install-hermes-light.sh`: builds Hermes Light (the remote-only Hermes Desktop, no local agent) from source in a throwaway container and installs it under `$HOME` with a launcher and menu entry; turns on keyring encryption for the sign-in token before the first launch. See `scripts/hermes-light/README.md`.

---

## [v1.0.0] - 2025-12-20

### 🎉 Initial stable release

First production-ready release of the Linux Dotfiles Onboarding system.

### Added
- One-line bootstrap script for new hosts
- Idempotent dotfiles deployment using GNU Stow
- Interactive onboarding menu powered by `gum`
- Category-based installs:
  - `core` (apt baseline, Flatpak, SSH)
  - `cli` (Neovim, Starship, shell tooling)
  - `desktop` (Flatpak-first GUI apps)
  - `security` (Proton tooling)
- Verification scripts per category
- Uninstall support per category
- Dry-run support
- Per-category human-readable README files
- State tracking under `~/.local/state/onboarding`

### Changed
- Adopted Omakub-style installation patterns for Neovim and gum
- Standardized repository handling using modern `signed-by` keyrings
- Moved onboarding master logic into a dedicated `master` component
- Centralized destructive operations into bootstrap only

### Removed
- Legacy `apt-key` usage
- Implicit repository modifications outside of `core`
- Datto APT repository management (packages left intact intentionally)

### Fixed
- Path resolution issues when running via symlinks
- gum installation failures on brand-new Ubuntu systems
- Stow conflicts caused by pre-existing shell configuration
- Silent menu failures caused by unselected options

---

## Future releases

Planned areas for future versions (not yet implemented):
- Host profiles (laptop / server)
- CI / non-interactive mode
- Zsh parity
- Repository audit tooling
- Version pinning

