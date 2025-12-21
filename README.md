# linux_dotfiles

Personal Linux dotfiles and shell environment configuration maintained by **elikesbikes**.

This repository contains opinionated, production‑tested configuration for Bash, terminal emulators, Neovim, Starship, and various CLI tools. It is designed for **Linux workstations and servers**, with an emphasis on repeatability, portability, and transparency.

> ⚠️ These dotfiles are tailored to the author's environment. Review before using and adapt as needed.

---

## Overview

The goal of this repository is to provide:

- A modular Bash environment (aliases, functions, exports split by concern)
- Consistent terminal and prompt experience across hosts
- A reproducible Neovim setup (Lazy.nvim‑based)
- Clear separation between **configuration**, **secrets**, and **machine‑specific state**
- Git‑tracked history with changelog and tagged releases

---

## Repository Structure

```
.
├── .bash/                  # Modular bash configuration
│   ├── aliases.sh          # Command aliases
│   ├── functions.sh        # Custom shell functions
│   ├── misc.sh             # Misc helpers and tweaks
│   ├── starship.sh         # Starship prompt integration
│   └── config.json         # Shell‑related config data
├── .bashrc                 # Main bash entry point
├── .config/                # User application configs
│   ├── alacritty/          # Alacritty terminal configuration
│   ├── kitty/              # Kitty terminal configuration
│   ├── nvim/               # Neovim (Lazy.nvim) configuration
│   ├── fastfetch/          # fastfetch system info
│   ├── neofetch/           # neofetch configuration
│   ├── starship.toml       # Starship prompt config
│   └── VeraCrypt/          # VeraCrypt user config
├── exports/                # Exported settings & OS‑level configs
├── .env                    # Environment variables (DO NOT COMMIT SECRETS)
├── CHANGELOG.md            # Versioned change history
└── README.md               # This file
```

---

## Bash Design

The Bash configuration is intentionally **modular**:

- `.bashrc` is minimal and sources files from `.bash/`
- Logic is split by responsibility (aliases, functions, prompt, misc)
- Designed to be readable, debuggable, and extensible

This avoids monolithic `.bashrc` files and makes iteration safer.

---

## Neovim

- Uses **Lazy.nvim** for plugin management
- Configuration written in Lua
- Clear separation between:
  - options
  - keymaps
  - autocmds
  - plugins
- Includes lockfile (`lazy-lock.json`) for reproducibility

Neovim config lives entirely under:

```
.config/nvim
```

---

## Terminal & Prompt

Supported / configured tools:

- **Kitty**
- **Alacritty**
- **Starship**
- **fastfetch / neofetch**

Themes and shared configuration are split into reusable `.toml` fragments where possible.

---

## Environment Variables

An `.env` file exists **by design**, but:

- It should contain **NO secrets** when committed
- Real secrets should live in a **local, untracked, user‑specific env file**
- This repo assumes env files are sourced explicitly by the shell

Always review `.env` before use.

---

## Installation (Manual)

This repository intentionally avoids automatic installers.

Typical usage:

```bash
git clone https://github.com/elikesbikes/linux_dotfiles.git ~/linux_dotfiles
cd ~/linux_dotfiles

# Review files carefully before symlinking or sourcing
```

Common approaches:
- Symlink individual files
- Source `.bashrc` selectively
- Copy `.config/*` entries you actually use

---

## Versioning & Stability

- Changes are tracked in `CHANGELOG.md`
- Git **tags** represent frozen, known‑good states
- `main` may evolve as experimentation continues

If stability matters, **use a tagged release**.

---

## Audience

This repo is best suited for:

- Linux power users
- Engineers / SREs / DevOps practitioners
- Users comfortable reading and modifying shell and Lua code

Not intended for beginners.

---

## License

Personal configuration repository.  
Reuse allowed, attribution appreciated.

---

## Disclaimer

These dotfiles reflect personal workflow decisions.  
No warranty, no guarantees — **read before running**.
