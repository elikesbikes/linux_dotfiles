# linux_dotfiles

Opinionated Linux dotfiles curated and battle-tested by **elikesbikes**.

This repository is not a generic dotfiles starter kit. It reflects a very specific workflow built over time across Linux workstations, servers, and homelab systems. The focus is on **clarity, control, and repeatability** — not magic installers or fragile abstractions.

If you like to know *exactly* what your shell and editor are doing, you're in the right place.

---

## Table of Contents

1. [Philosophy](#1-philosophy)
2. [Repository Layout](#2-repository-layout)
3. [Installation & Deployment (GNU Stow)](#3-installation--deployment-gnu-stow)
4. [Onboarding System](#4-onboarding-system)
5. [CI/CD Pipeline](#5-cicd-pipeline)
6. [Sudoers Management](#6-sudoers-management)
7. [Bash Setup](#7-bash-setup)
8. [Neovim](#8-neovim)
9. [Terminal & Prompt](#9-terminal--prompt)
10. [Scripts Library](#10-scripts-library)
11. [Environment Variables](#11-environment-variables)
12. [Versioning & Stability](#12-versioning--stability)
13. [Who This Is For](#13-who-this-is-for)
14. [License](#14-license)

---

## 1. Philosophy

These dotfiles follow a few non-negotiable principles:

- **Explicit over clever** – readable configs beat one-liners
- **Modular over monolithic** – small, focused files by concern
- **Idempotent over destructive** – everything is safe to re-run
- **Versioned and frozen** – tags represent known-good states
- **Portable, not universal** – adapt to your system, don't blindly copy

This repo is meant to be **read**, not just cloned.

---

## 2. Repository Layout

```
.
├── .bash/                  # Modular bash environment
│   ├── aliases.sh          # Aliases and shortcuts
│   ├── functions.sh        # Custom shell functions
│   ├── misc.sh             # Quality-of-life tweaks
│   ├── starship.sh         # Prompt integration
│   └── config.json         # Shell-related config data
├── .bashrc                 # Main bash entry point (minimal, sourced logic)
├── .config/                # Application configuration
│   ├── alacritty/          # Alacritty terminal
│   ├── kitty/              # Kitty terminal
│   ├── nvim/               # Neovim (Lazy.nvim, Lua)
│   ├── fastfetch/          # fastfetch system info
│   ├── neofetch/           # neofetch config
│   ├── starship.toml       # Starship prompt config
│   └── VeraCrypt/          # VeraCrypt user config
├── exports/                # Exported desktop / OS-level settings (dconf, keys)
├── scripts/                # Onboarding system + standalone homelab scripts
│   ├── onboarding/         # Idempotent, gum-driven host onboarding
│   ├── linux/              # DDNS, firewall, keybindings, sudoers helpers
│   ├── proxmox/            # Proxmox backup notifications
│   ├── truenas/            # Replication monitoring
│   └── urbackup/           # Snapshot / backup tooling
├── sudoers/                # Versioned drop-in sudoers policy (sudoers.d/)
├── .unison/                # Unison sync profiles
├── .stow-local-ignore      # Files Stow must NOT symlink into $HOME
├── .gitlab-ci.yml          # Auto-deploy pipeline (fleet sync)
├── PIPELINE.md             # CI/CD deployment documentation
├── CHANGELOG.md            # Human-readable change history
└── README.md               # This file
```

---

## 3. Installation & Deployment (GNU Stow)

Configuration is deployed with **GNU Stow** — the repo root is the Stow package, and files are symlinked into `$HOME`.

```bash
git clone https://github.com/elikesbikes/linux_dotfiles.git ~/devops/github/linux_dotfiles
cd ~/devops/github/linux_dotfiles
stow . -t ~
```

Symlinks mean changes are picked up **instantly** — edit a tracked file (or `git pull`) and your live config updates with no copy step and no restart.

Files that must stay in the repo and **not** be symlinked into `$HOME` are listed in `.stow-local-ignore` (e.g. `README.md`, `CHANGELOG.md`, `PIPELINE.md`, `.gitlab-ci.yml`, `.env`).

---

## 4. Onboarding System

For a **fresh host**, `scripts/onboarding/` turns a bare Ubuntu/Debian GNOME install into a fully configured workstation. It is fully **idempotent** — every installer is safe to re-run.

One-line bootstrap:

```bash
wget -qO- https://raw.githubusercontent.com/elikesbikes/linux_dotfiles/refs/heads/main/scripts/onboarding/scripts/dotfiles/install_dotfiles.sh | bash
```

This clones the repo, installs `git` + `stow`, removes conflicting defaults, deploys dotfiles via Stow, and launches an interactive `gum`-powered menu.

Work is split into auto-discovered **categories**, each a directory of small `install_*.sh` scripts with matching verify/uninstall support:

| Category     | Installs                                   |
|--------------|--------------------------------------------|
| `core`       | apt baseline, Flatpak, SSH                 |
| `cli`        | Neovim, Starship, shell tooling            |
| `desktop`    | Flatpak-first GUI apps                     |
| `security`   | Proton tooling                             |
| `extensions` | GNOME shell extensions                     |
| `themes`     | Theming                                    |
| `dotfiles`   | Stow deployment of this repo               |

State is tracked under `~/.local/state/onboarding/`. See `scripts/onboarding/README.md` for full details.

---

## 5. CI/CD Pipeline

Pushing dotfile changes **auto-deploys to the entire homelab fleet** via GitLab CI. The repo has two push remotes (GitHub + GitLab); the pipeline runs on every push to `main`.

```
gacp_dotfiles "message"  →  push to GitHub + GitLab
                              ↓
            GitLab pipeline SSHes into each host:
            git fetch origin && git reset --hard origin/main
                              ↓
            Symlinks pick up changes instantly
```

Hosts updated by the pipeline: `docker-prod-1`, `endurance`, `gargantua`, `ranger0`, `ranger1`, `tars`, `trainerroad2` (offline hosts are skipped gracefully). When `sudoers/` changes, the pipeline additionally runs `scripts/sync-sudoers-ci.sh` on each host. Full details and host onboarding steps are in `PIPELINE.md`.

> ⚠️ Because each host is **hard-reset to `origin/main`**, any change saved to disk but not committed *and* pushed is silently wiped on the next sync. Edit → commit → push.

---

## 6. Sudoers Management

`sudoers/sudoers.d/` holds versioned, numbered drop-in policy files deployed to each host's `/etc/sudoers.d/`:

| File              | Purpose                          |
|-------------------|----------------------------------|
| `00-defaults`     | Global `Defaults` settings       |
| `10-admin`        | Admin privileges                 |
| `20-diagnostics`  | Diagnostic commands              |
| `30-filesystem`   | Filesystem operations            |
| `40-scripts`      | Script execution grants          |

Deployment is handled automatically by the CI pipeline (`scripts/sync-sudoers-ci.sh`) only when files under `sudoers/` change.

---

## 7. Bash Setup

The Bash environment is intentionally **split by responsibility**.

- `.bashrc` does very little on purpose
- Everything interesting lives in `.bash/`
- Each file has a single job

This makes it easier to debug, extend, or remove pieces without breaking your shell. If something goes wrong, you'll know *where* and *why*.

---

## 8. Neovim

Neovim is configured using:

- **Lazy.nvim** for plugin management
- Lua for all configuration
- Locked dependencies via `lazy-lock.json`

Structure is clean and predictable:

- `options.lua` – editor behavior
- `keymaps.lua` – mappings only
- `autocmds.lua` – event-driven logic
- `plugins/` – plugin specs and overrides

Everything lives under `.config/nvim`. No global hacks. No mystery state.

---

## 9. Terminal & Prompt

This repo configures a consistent terminal experience across hosts:

- **Kitty**
- **Alacritty**
- **Starship**
- **fastfetch / neofetch**

Themes and shared settings are broken into reusable fragments instead of copy-pasted blobs.

---

## 10. Scripts Library

Beyond onboarding, `scripts/` ships standalone homelab tooling. Each directory has its own `README.md`:

| Path                              | Purpose                                      |
|-----------------------------------|----------------------------------------------|
| `scripts/linux/DDNS/`             | Dynamic DNS updater                          |
| `scripts/linux/firewall-external/`| External firewall rule application           |
| `scripts/linux/idrive-monitor/`   | iDrive backup monitoring                     |
| `scripts/linux/keybindings/`      | GNOME keybinding backup / restore            |
| `scripts/linux/sudoers/`          | Local sudoers sync helper                    |
| `scripts/proxmox/`                | Proxmox backup ntfy notifications            |
| `scripts/truenas/`                | TrueNAS replication monitoring               |
| `scripts/urbackup/`               | UrBackup snapshot tooling (LVM / non-LVM)    |

---

## 11. Environment Variables

An `.env` file exists to document **structure**, not secrets.

Rules:

- ❌ Do not commit secrets
- ✅ Keep real values in a local, ignored env file
- ✅ Source env files explicitly

If you don't know what a variable does, don't set it.

---

## 12. Versioning & Stability

- `CHANGELOG.md` explains *why* things changed
- Git **tags** represent frozen, known-good states
- `main` is allowed to evolve (and auto-deploys to the fleet)

If you care about stability, **check out a tag**.

---

## 13. Who This Is For

This repo is for:

- Linux power users
- Engineers, SREs, DevOps, homelabbers
- People who enjoy understanding their tools

If you want plug-and-play dotfiles, this probably isn't it.

---

## 14. License

Personal configuration repository.

Reuse what's useful. Attribution appreciated.

---

## Final Note

These dotfiles match *my* brain and workflow.

Steal ideas, not assumptions.
</content>
</invoke>
