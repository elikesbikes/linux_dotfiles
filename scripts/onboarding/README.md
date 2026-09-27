# Linux Dotfiles Onboarding

A complete, **idempotent** onboarding system for fresh Linux hosts (Ubuntu/Debian-based, GNOME). It installs system software, CLI tools, desktop applications, and security tooling, then deploys user configuration via **direct symlinks** (`dotfiles/create-managed-symlinks.sh`) — all driven by an interactive `gum`-powered menu. (GNU Stow is installed as a CLI tool by `cli/install_stow.sh`, but it is not what deploys the dotfiles.)

## Table of Contents

1. [Overview](#1-overview)
2. [One-line Bootstrap](#2-one-line-bootstrap)
3. [Architecture](#3-architecture)
4. [Categories](#4-categories)
5. [Usage](#5-usage)
6. [State Tracking & Logs](#6-state-tracking--logs)
7. [Design Principles](#7-design-principles)
8. [Requirements](#8-requirements)

## 1. Overview

The onboarding system turns a bare Linux install into a fully configured workstation. Work is split into **categories**, each a directory of small, self-contained, idempotent `install_*.sh` scripts. A master menu orchestrates install / verify / uninstall by category. Every script is safe to re-run: it checks a state marker (and/or the installed binary) before doing any work.

## 2. One-line Bootstrap

Run on a new host to clone the repo and create managed symlinks:

```bash
wget -qO- https://raw.githubusercontent.com/elikesbikes/linux_dotfiles/refs/heads/main/scripts/onboarding/scripts/dotfiles/create-managed-symlinks.sh | bash
```

This will:
- Clone the dotfiles repository to `~/devops/github/linux_dotfiles` (or pull latest if it exists)
- Configure dual-remote push (GitHub + GitLab) on fresh clones
- Create managed symlinks from `$HOME` into the repo (OS-aware)
- Back up any existing files before replacing them

Then launch the onboarding menu: `bash ~/scripts/onboarding/scripts/master/master.sh`

## 3. Architecture

```
scripts/
├── master/      # Interactive gum menu (entry point after bootstrap)
├── core/        # Foundational system setup (run first)
├── cli/         # Command-line tools
├── desktop/     # GUI applications (apt / snap / flatpak)
├── security/    # Proton privacy suite
├── extensions/  # GNOME Shell extensions (declarative via extensions.conf)
├── themes/      # User-level Brave theme scripts (standalone, not in the master menu)
├── dotfiles/    # Bootstrap + managed-symlink deployment
└── verify/      # Audit-only verification scripts per category
```

Each category directory contains `install_*.sh` scripts auto-discovered by the master menu, plus a `README.md` describing it. `themes` and `security/setup-ssh-key.sh` are standalone scripts run directly — not menu-driven categories.

## 4. Categories

| Category | Purpose | Source |
|----------|---------|--------|
| `core` | sudo (classic, not sudo-rs), SSH client, Flatpak/Flathub, Kitty (+terminfo), Node.js — apt refresh happens here | apt |
| `cli` | Neovim, Starship, direnv, zoxide, stow, fastfetch (GitHub release), figlet, exa/eza, yazi, unison, build-essential, sudoers drop-ins, default editor | apt / GitHub release / official installer |
| `desktop` | Timeshift, Spotify, RustDesk, Todoist, Flatpak GUI apps | apt / snap / flatpak |
| `security` | Proton VPN, Mail Desktop, Mail Bridge, Pass, Authenticator | official `.deb` |
| `extensions` | GNOME Shell extensions reconciled from `extensions.conf` | gext |

`themes` (Brave Catppuccin Macchiato/Mocha) is a standalone category: it has no `master.sh` menu entry and is run directly, e.g. `bash scripts/themes/apply_brave_catppuccin_mocha.sh`.

## 5. Usage

After bootstrap (or any time), launch the menu directly:

```bash
bash scripts/master/master.sh
```

From the menu you can:
- **Install components** — pick one or more of `core`, `cli`, `desktop`, `security`, `extensions`
- **Verify system** — run audit-only checks per category
- **Uninstall components** — remove by category (where supported)

`themes` and `security/setup-ssh-key.sh` are not listed in the menu; run them directly (see their category READMEs).

A category is only marked installed if **all** its installers succeed; a failing installer is reported and skipped without tearing down the menu.

## 6. State Tracking & Logs

- **Install markers:** `~/.local/state/onboarding/installed/<name>`
- **Logs:** `~/.local/state/onboarding/logs/<script>.log`
- **Backups (themes):** `~/.local/state/onboarding/backups/`

Paths honor `XDG_STATE_HOME` when set. Re-running an already-installed script is a no-op thanks to these markers.

## 7. Design Principles

- **Categories are independently runnable** — since any category can be selected on its own without `core` running first, `desktop` and `security` each refresh `apt` themselves before installing (e.g. after adding a new repo). `cli` assumes the cache is already fresh from `core`.
- **Idempotent** — every script is safe to re-run; state-tracked markers
- **gum is UX only** — no hidden execution behind the menu
- **Official sources** — third-party repos added explicitly with modern signed keyrings
- **Configuration via dotfiles** — managed exclusively through direct symlinks (`dotfiles/create-managed-symlinks.sh`), not GNU Stow

## 8. Requirements

- A Debian/Ubuntu-based distribution with `apt`
- `sudo` privileges
- GNOME (for the `extensions` category)
- Internet access
- `gum` is auto-installed by the master menu on first run

Author TARS