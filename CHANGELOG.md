# Changelog

All notable changes to this repository will be documented in this file.

This project follows a pragmatic versioning model inspired by
[Semantic Versioning](https://semver.org/).

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

