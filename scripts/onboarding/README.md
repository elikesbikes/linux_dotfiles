# Linux Dotfiles Onboarding

A complete, **idempotent** onboarding system for fresh Linux hosts (Ubuntu/Debian-based, GNOME). It installs system software, CLI tools, desktop applications, and security tooling, then deploys user configuration via **direct symlinks** (`dotfiles/create-managed-symlinks.sh`) — all driven by an interactive `gum`-powered menu. GNU Stow is installed as a CLI tool (`cli/install_stow.sh`) but is not what deploys the dotfiles.

## Table of Contents

1. [Overview](#1-overview)
2. [One-line Bootstrap](#2-one-line-bootstrap)
3. [Architecture](#3-architecture)
4. [Categories](#4-categories)
5. [Standalone Scripts](#5-standalone-scripts)
6. [Usage](#6-usage)
7. [Verification](#7-verification)
8. [State Tracking & Logs](#8-state-tracking--logs)
9. [Design Principles](#9-design-principles)
10. [Requirements](#10-requirements)

## 1. Overview

The onboarding system turns a bare Linux install into a fully configured workstation. Work is split into **categories**, each a directory of small, self-contained, idempotent `install_*.sh` scripts. A master menu (`scripts/master/master.sh`) orchestrates install / verify / uninstall by category. Every script is safe to re-run: it checks a state marker (and/or the installed binary) before doing any work.

## 2. One-line Bootstrap

Run on a new host to clone the repo and create managed symlinks:

```bash
wget -qO- https://raw.githubusercontent.com/elikesbikes/linux_dotfiles/refs/heads/main/scripts/onboarding/scripts/dotfiles/create-managed-symlinks.sh | bash
```

This will:
- Clone the dotfiles repository to `~/devops/github/linux_dotfiles` (or pull latest if it exists)
- Configure dual-remote push (GitHub + GitLab) on fresh clones
- Create managed symlinks from `$HOME` into the repo (OS-aware — e.g. Hyprland/kitty/omarchy links only created on Omarchy hosts)
- Back up any existing files before replacing them with symlinks

Then launch the onboarding menu:

```bash
bash ~/scripts/onboarding/scripts/master/master.sh
```

## 3. Architecture

```
scripts/
├── master/      # Interactive gum menu (entry point after bootstrap)
├── core/        # Foundational system setup (run first)
├── cli/         # Command-line tools
├── desktop/     # GUI applications (apt / snap / flatpak)
├── security/    # Proton privacy suite (+ standalone setup-ssh-key.sh)
├── extensions/  # GNOME Shell extensions (declarative via extensions.conf)
├── themes/      # User-level Brave theme scripts (standalone, not in the master menu)
├── dotfiles/    # Bootstrap + managed-symlink deployment
└── verify/      # Audit-only verification scripts per category
```

Each menu-driven category directory contains `install_*.sh` scripts auto-discovered by `master.sh`, plus a `README.md` describing it. `themes` and `security/setup-ssh-key.sh` are standalone scripts run directly — see [Standalone Scripts](#5-standalone-scripts).

## 4. Categories

These five are driven by the master menu (`Install components` / `Verify system` / `Uninstall components`):

| Category | Purpose | Source |
|----------|---------|--------|
| `core` | sudo (classic, not sudo-rs), SSH client, Flatpak/Flathub, Kitty (+terminfo), Node.js | apt |
| `cli` | Neovim, Starship, direnv, zoxide, stow, fastfetch, figlet, exa/eza, yazi, unison, build-essential, sudoers drop-ins, default editor | apt / GitHub release / official installer |
| `desktop` | Timeshift, Spotify, RustDesk, Todoist, Flatpak GUI apps | apt / snap / flatpak |
| `security` | Proton VPN, Mail Desktop, Mail Bridge, Pass, Authenticator | official `.deb` |
| `extensions` | GNOME Shell extensions reconciled from `extensions.conf` | gext (pipx) |

Notable non-apt installs worth calling out (see each category's own `README.md` for full detail):
- `cli/install_fastfetch.sh` pulls the **latest GitHub release** `.deb`, not the apt version, because the apt version lacks Kitty graphics auto-detection; it also installs `imagemagick` for image logo rendering.
- `cli/install_zz_sudoers.sh` and `cli/install_zz_default_editor.sh` run last in the `cli` category (hence the `zz_` prefix) — they deploy sudoers drop-ins and set the system default editor to nvim, and depend on `unison`/`nvim` having already been installed earlier in the same category.

## 5. Standalone Scripts

Not registered in `master.sh` — run these directly:

| Script | Purpose |
|--------|---------|
| `themes/apply_brave_catppuccin_macchiato.sh` | Patches Brave's `Preferences` to the Catppuccin Macchiato palette |
| `themes/apply_brave_catppuccin_mocha.sh` | Patches Brave's `Preferences` to the Catppuccin Mocha palette |
| `security/setup-ssh-key.sh <hostname>` | Bootstraps SSH key access for `ecloaiza` on a new remote host via the Proton Pass SSH agent |

```bash
bash scripts/themes/apply_brave_catppuccin_mocha.sh
bash scripts/security/setup-ssh-key.sh <hostname>
```

## 6. Usage

After bootstrap (or any time), launch the menu directly:

```bash
bash scripts/master/master.sh
```

From the menu you can:
- **Install components** — pick one or more of `core`, `cli`, `desktop`, `security`, `extensions`
- **Verify system** — run audit-only checks per category
- **Uninstall components** — runs any `uninstall_*.sh` present in a category

A category is only marked installed if **all** its installers succeed; a failing installer is reported and skipped without tearing down the menu.

> **Note:** the uninstall menu path is implemented in `master.sh`, but no category currently ships an `uninstall_*.sh` script — selecting "Uninstall components" today is a no-op for every category. Add `uninstall_<tool>.sh` files (mirroring the matching `install_<tool>.sh`) to make a category's uninstall actually do something.

## 7. Verification

Each menu category has an audit-only verifier under `scripts/verify/` (extensions verifies itself via `extensions/verify_extensions.sh`). Verifiers never modify the system — they check for expected commands/packages and exit with the count of failed checks.

```bash
bash scripts/verify/verify_cli.sh
echo "exit code = $?"   # 0 = all checks passed
```

Run from the master menu's **Verify system** option, or directly per category.

## 8. State Tracking & Logs

- **Install markers:** `~/.local/state/onboarding/installed/<name>`
- **Logs:** `~/.local/state/onboarding/logs/<script>.log`
- **Backups (themes):** `~/.local/state/onboarding/backups/brave/`

Paths honor `XDG_STATE_HOME` when set. Re-running an already-installed script is a no-op thanks to these markers.

## 9. Design Principles

- **Categories are independently runnable** — `desktop` and `security` each refresh `apt` themselves before installing (e.g. after adding a new repo); `cli` assumes the cache is already fresh from `core`.
- **Idempotent** — every script is safe to re-run; state-tracked markers
- **gum is UX only** — no hidden execution behind the menu
- **Official sources** — third-party repos added explicitly with modern signed keyrings
- **Configuration via dotfiles** — managed exclusively through direct symlinks (`dotfiles/create-managed-symlinks.sh`), not GNU Stow

## 10. Requirements

- A Debian/Ubuntu-based distribution with `apt`
- `sudo` privileges
- GNOME (for the `extensions` category)
- Internet access
- `gum` is auto-installed by the master menu on first run

Author TARS
