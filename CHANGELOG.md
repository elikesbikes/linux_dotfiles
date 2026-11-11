# Changelog

All notable changes to this repository will be documented in this file.

This project follows a pragmatic versioning model inspired by
[Semantic Versioning](https://semver.org/).

---

## [v1.15.2] - 2026-11-11

### Fixed
- `scripts/gitlab-runner/gitlab-runner-proton.sh` and `gitlab-runner-proton-macos.sh` started the runner with the `umask 077` they set for the RAM config. The runner passes its umask to every job, so since 2026-11-08 every file a shell-runner job wrote (deploy `git reset --hard`, builds) was owner-only on murph, rocky, hailmary, tars, endurance and kipp. Visible break: the Hermes vault gate (user `hermes-vault` on hailmary) failed every read with `PermissionError`, because it imports MCC's `shared/auth_policy.py`, which a deploy had written as `600`. Both launchers now set `umask 022` just before `exec`; the config stays private inside its `700` RAM folder.

Repair of files already written owner-only (only files from the repos, changed since 2026-11-08; state, data and secrets untouched): git checkouts on murph 106, rocky 328, hailmary 333 (mcc, adastra, tutorials, dotfiles); deployed `~/devops/docker` copies on rocky 27 and hailmary 29 (ntfytars-relay, watchyourlan, gitlab-runner / gitlab) and endurance 11 files + 4 folders (hermes, `data/` left at 700). All six runners restarted 13:02-13:04 (no job running); Linux runner processes show `Umask: 0022`.

Tested: the Hermes container on endurance (as user `hermes`) lists and reads Homelab notes through the gate again (`outcome=ok`, 106 notes); affected containers healthy. Not tested: a new deploy writing a file (next pipeline will show it); kipp's runner umask (macOS has no /proc; next iOS job).

---

## [v1.15.1] - 2026-11-09

### Fixed
- `scripts/onboarding/scripts/security/setup-ssh-key.sh` followed the old key model: it looked up a `<target> SSH Key` in the agent, saved it as `~/.ssh/pubkeys/<target>.pub` and pinned it per target, which is the "key named after the host you log in to" pattern the v1.14.0 identity model replaced. It now installs the running host's own `~/.ssh/identity.pub` (checked against the agent, setup steps printed when missing) and adds only a `HostName`/`User` alias; user, sudo, OS and Windows handling are unchanged. Onboarding READMEs updated.

Tested: the identity path and the no-identity error against an unreachable test address (no side effects: `known_hosts` and `~/.ssh/config` unchanged). Not tested end to end against a fresh host.

---

## [v1.15.0] - 2026-11-09

### Added
- SSHTars devices sign only as themselves. `scripts/proton-pass/ssh-agent-start.sh --device <name>` serves the Proton vault `SSH <name>` (one key titled `SSHTars device identity`) on `~/.ssh/sshtars-<name>.sock`; the user unit `scripts/proton-pass/systemd/proton-pass-ssh-agent-device@.service` runs one per device on hailmary (`tars-iphone2`, `tars-ipad`). No HOMELAB fallback in device mode.

### Changed
- `scripts/sshtars/broker`: the `agent` request now pipes to the device's own socket (`~/.ssh/sshtars-<device>.sock`) instead of hailmary's HOMELAB agent, refuses a device name outside `a-z 0-9 -`, and logs an error when that device's agent is not running. Before this, every device signed with the one shared `tars-iphone` key from HOMELAB. Same change in the sshtars-ios repo `tools/broker/`.
- `scripts/sshtars/catalog.py`: docstring for the new key naming (the catalog's `key:` is now `SSHTars device identity`).
- `scripts/certbot/certbot-renew.sh` (canary) and `hooks/deploy_to_unifi.sh`: pin `~/.ssh/identity.pub` (hailmary's own Proton identity key) instead of `~/.ssh/id_ed25519.pub`, for hailmary's switch to its own vault.

Tested, 2026-11-09: both device agents list exactly one key; each device key logs in to all 9 reachable catalog hosts (tars, rocky, hailmary, kipp, endurance, trainerroad, router, proxmox-prod-6s, nvr-prod-2) through the device's socket. Not tested: the app on the devices (needs a catalog sync by the owner); gargantua (offline).

---

## [v1.14.0] - 2026-11-09

### Changed
- `scripts/proton-pass/ssh-agent-start.sh`: the SSH agent now serves **only the host's own key**, from the Proton vault `SSH <short hostname>` (one key, `<host> SSH identity`), instead of all ~21 keys in HOMELAB. Owner rule (2026-10-09): each host signs only as itself; before this, any host could sign as any other, and some did (endurance and murph pinned other hosts' keys).
  - Vault choice: per-host override `~/.config/proton-pass/ssh-agent-vault`, else `SSH <host>`, else HOMELAB with a syslog warning (case and gargantua until they are migrated).
  - Each host's PAT has viewer access to its own SSH vault only.
  - hailmary keeps HOMELAB through the override until the SSHTars iPhone/iPad keys get their own agents.
- Each host's `~/.ssh/config` (not in this repo) now pins only `~/.ssh/identity.pub` under `Host *`; every per-target `IdentityFile` was removed.

### Added
- `scripts/proton-pass/README.md`: the identity model, how the agent picks its vault, how to add a host.

Tested, 2026-11-09:
- Temporary agent per host on its own vault, logins pinned to the new key: full mesh of tars, hailmary, rocky, endurance, murph, kipp, trainerroad (42/42); tars to 15 infra and mesh targets (router, Proxmox 1s/4s/6s, PDM, Home Assistant, three Windows hosts); hailmary to the router (certbot).
- After the switch, through the real agent and config: tars 15/15; rocky, murph, endurance, kipp, trainerroad 6/6 each; `ssh-add -l` shows one key on each.

Not tested: case and gargantua (offline); hailmary (override until the SSHTars change).

---

## [v1.13.0] - 2026-11-09

### Added
- `scripts/hermes-vault`: Hermes on endurance can now **read** the owner's homelab docs in the Obsidian vault (`IT/github/adastra/Homelab/`), read-only (owner's choice, 2026-11-09). Before this, Hermes in Open WebUI could not see them and suggested mounting or cloning the vault, which doesn't fit (the vault lives in CouchDB on hailmary).
  - `vaultgate.py`: `IT/github/adastra/Homelab/` added to the read roots (`list`, `get`), up to 12 path parts deep (the deepest note has 10). Writing is still only allowed under `Career/Courses/`, create-only.
  - `update-gate.sh` (new): on hailmary, `sudo ~/scripts/hermes-vault/update-gate.sh` installs only the gate program, keeps the old one as `vaultgate.py.prev`, and self-tests (a Homelab write must be refused; a real Homelab `list`).
  - The Hermes skill that uses it, `devops/homelab-notes`, lives in the hermes-config repo.

Tested: 51 gate tests pass (13 new), and all 296 real Homelab note paths pass the gate's path rules. The note sizes fit the gate's 512 KiB output cap (the Findings Backlog is 255 KiB).

Live, 2026-11-09:
- The owner ran `update-gate.sh` on hailmary. The self-test refused a Homelab write and listed `Homelab/infra/`.
- From Hermes' container, `list` and `get` work; the Findings Backlog came back whole (260,622 bytes). A Homelab `create` and a `Finances/` read were refused.
- A real Hermes chat ("what revision is my Honcho note?") picked the skill without being told and answered rev 10 / 2026-11-08 12:25, which matches the vault. The test chat was then deleted from Hermes and from Honcho.

Not tested: Discord, and Open WebUI after this change. Both use the same Hermes and skills.

## [v1.12.0] - 2026-11-09

### Changed
- Hyprland on tars: back to one global workspace numbering, as before Omarchy 4.5.0 (owner's choice). The ultrawide has 1-8, the Dell has 9, and numbers no longer change when a monitor turns off. Omarchy 4.5.0's per-monitor workspaces gave the Dell 11-20 and renumbered a monitor's workspaces onto the other screen while it was off, putting them back when it returned. This replaces the v1.11.2 "Super + 9 = Dell" keys.
  - `.config/hypr/monitors.lua`: `o.workspaces.reconcile` is a no-op, which switches off Omarchy's re-sorting on Hyprland start, config reload and monitor add/remove. The rule "workspace 9 on the Dell, default" is back.
  - `.config/hypr/bindings.lua`: `SUPER (+ SHIFT / + SHIFT + ALT) + 1-0` go to the plain workspaces 1-10 again, and `SUPER + SHIFT + ALT + arrows` move a workspace to another monitor without renumbering it (`o.workspace_to_monitor`).
  - `.config/omarchy/plugins/ecloaiza.workspaces/`: a clone of the bar's `omarchy.workspaces` widget (`omarchy plugin clone`, and the bar in `~/.config/omarchy/shell.json` switched to it). Every bar shows the same global numbers and a click goes to the plain workspace.
  - After every Omarchy update, check that `/usr/share/omarchy/default/hypr/monitor-workspaces.lua` still exposes `o.workspaces.reconcile`, and that the stock widget hasn't gained fixes worth copying.

Tested: `hyprctl reload` with no config errors, and each workspace key is bound once. The Dell stayed on workspace 9 through a config reload, which it would not have done with Omarchy's re-sorting on. After a shell restart both bars show `1 2 3 4 5 7 9`. Not tested: pressing the keys (simulated key presses with `wtype` don't trigger Hyprland key binds), turning the monitors off and on, and a fresh login. The shell log warning "Handler was registered but will not be used ... target omarchy.workspaces" (one per extra screen) also comes from the stock widget; it is not from this change.

## [v1.11.2] - 2026-11-09

### Fixed
- Hyprland on tars: the Dell U2719DX was no longer "workspace 9". Omarchy 4.5.0 (installed 2026-11-08) gave every monitor its own workspaces 1-10 (`/usr/share/omarchy/default/hypr/monitor-workspaces.lua`, no switch to turn it off): the ultrawide keeps ids 1-10, the Dell gets 11-20 and its bar shows them as 1-10. It re-applies that at every Hyprland start, config reload and monitor change, so a reboot doesn't undo it.
  - `.config/hypr/bindings.lua`: `SUPER + 9` focuses the Dell, `SUPER + SHIFT + 9` sends the active window to the workspace the Dell shows (and follows), `SUPER + SHIFT + ALT + 9` does the same without following. The Dell is found by make/model/serial, not by connector.
  - `.config/hypr/monitors.lua`: removed the old rule pinning workspace 9 to the Dell as its default (it fought Omarchy's per-monitor model); workspaces 1-8 stay pinned to the ultrawide.

Tested: `hyprctl reload` with no config errors; the three binds are registered; `hyprctl dispatch 'o.dell_focus()'` moved focus to the Dell. Not tested: the two move-window keys (they would have moved one of the owner's windows), and a fresh login.

## [v1.11.1] - 2026-11-08

### Fixed
- `scripts/checkmk-local/gitlab_runner` (endurance): the CheckMK service "GitLab runner" went WARN ("config mode ?") after v1.11.0, because it still read `~/.gitlab-runner/config.toml`, which no longer exists. It now checks the RAM config `/run/user/<uid>/gitlab-runner/config.toml` (must be mode 600) and warns if a token file shows up on disk again.

Tested: run by hand on endurance after installing it to `/usr/lib/check_mk_agent/local/`: `0 "GitLab runner" ... RAM config mode 600`. Not tested: the WARN paths (no config, token file on disk).

## [v1.11.0] - 2026-11-08

### Changed
- Every other GitLab runner now keeps its token only in Proton Pass, like the deploy runners since v1.10.0. Each token was reset through the GitLab API straight into its Proton item (never printed); the old on-disk configs were shredded.
  - **tars (10) and endurance (11)** use `gitlab-runner-proton.service`; tars's old `gitlab-runner-tars.service` is disabled.
  - **kipp (3)** gets the macOS twin `scripts/gitlab-runner/gitlab-runner-proton-macos.sh` and the LaunchAgent `com.elikesbikes.gitlab-runner-proton.plist`: the PAT comes from kipp's no-TPM file and the config sits on an 8 MB RAM disk at `~/.gitlab-runner-ram/mnt`. The token is not passed through the environment, because shell jobs inherit it.
  - **Docker runners rocky-docker (6) and hailmary's homelab-docker-runner (1)**: new `scripts/gitlab-runner/gitlab-runner-docker-proton.sh` / `.service` pipe the config (templates `docker-rocky.toml`, `docker-hailmary.toml`, placeholder `@TOKEN@`) into the container's tmpfs `/etc/gitlab-runner` through `docker exec`, again after every container start (`docker events`). The compose files (tutorials `gitlab-runner`, `gitlab`) mount the tmpfs instead of a volume or `./runner-config`.
- `PIPELINE.md` (new section "The other homelab runners") and README: no runner token on disk anywhere.

Tested: tars, endurance, kipp and rocky-docker online in GitLab with no token in any file; hailmary's runner 1 checked after this push (result in the vault GitLab note). Not tested: a real job on kipp (iOS build), on tars, or on either Docker runner.

## [v1.10.1] - 2026-11-08

### Fixed
- `scripts/checkmk-local/honcho_queue` (endurance): the CheckMK check "Honcho API" was CRIT ("not answering (ERR HTTPError)") since Honcho's login was turned on (2026-11-08 ~07:50), because it read the queue without a key (401), and it added about two "No access token" errors a minute to Honcho's log. It now makes a 60-second workspace key inside the `honcho-api` container with Honcho's own `create_jwt` and the container's `AUTH_JWT_SECRET`; the secret never leaves the container and no key is stored.

Tested: shell syntax; run by hand on endurance it prints `0 "Honcho memory queue" pending=6 ... completed=11` instead of the CRIT line; installed copy runs the same. Not tested: the next CheckMK service discovery/check cycle on the CheckMK server (owner can watch the service turn OK).

Tag note: the `v1.10.1` tag was created later (2026-11-08 ~12:40, owner's choice), on the commit that finalises this note, so it also contains the gitlab-runner Proton work committed in between (`1ea0b7d`..`a4d03f6`, `scripts/gitlab-runner/`). That work is not described here; it gets its own entry when it is released.

## [v1.10.0] - 2026-11-08

### Changed
- rocky and hailmary runners (`rocky-shell` 8, `hailmary-shell` 9) now start like murph's: `gitlab-runner-proton.service` reads the token from Proton Pass (`gitlab-runner token - rocky` / `- hailmary`) and keeps `config.toml` in RAM. Both tokens were reset through the GitLab API straight into Proton (never printed), so the old on-disk tokens no longer work; the old `~/.gitlab-runner/config.toml` files were shredded. On rocky this also ends the double runner (`gitlab-runner.service` + `gitlab-runner-shell.service` on one config); both old units are disabled.
- `PIPELINE.md`, README and the script header: no runner token on disk on any deploy host.

Tested: both runners online in GitLab with their config only in `/run/user/1000/gitlab-runner/`; no `glrt-` token in any `.toml` under `~` on either host. This push's pipeline is the end-to-end check on all three hosts.

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

