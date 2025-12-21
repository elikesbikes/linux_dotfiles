# linux_dotfiles

Opinionated Linux dotfiles curated and battle-tested by **elikesbikes**.

This repository is not a generic dotfiles starter kit. It reflects a very specific workflow built over time across Linux workstations, servers, and homelab systems. The focus is on **clarity, control, and repeatability** — not magic installers or fragile abstractions.

If you like to know *exactly* what your shell and editor are doing, you’re in the right place.

---

## Philosophy

These dotfiles follow a few non-negotiable principles:

- **Explicit over clever** – readable configs beat one-liners
- **Modular over monolithic** – small, focused files by concern
- **Manual over automatic** – no surprise installers or hidden side effects
- **Versioned and frozen** – tags represent known-good states
- **Portable, not universal** – adapt to your system, don’t blindly copy

This repo is meant to be **read**, not just cloned.

---

## Repository Layout

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
├── exports/                # Exported desktop / OS-level settings
├── .env                    # Environment variables (structure only)
├── CHANGELOG.md            # Human-readable change history
└── README.md               # This file
```

---

## Bash Setup

The Bash environment is intentionally **split by responsibility**.

- `.bashrc` does very little on purpose
- Everything interesting lives in `.bash/`
- Each file has a single job

This makes it easier to debug, extend, or remove pieces without breaking your shell.

If something goes wrong, you’ll know *where* and *why*.

---

## Neovim

Neovim is configured using:

- **Lazy.nvim** for plugin management
- Lua for all configuration
- Locked dependencies via `lazy-lock.json`

Structure is clean and predictable:

- `options.lua` – editor behavior
- `keymaps.lua` – mappings only
- `autocmds.lua` – event-driven logic
- `plugins/` – plugin specs and overrides

Everything lives under:

```
.config/nvim
```

No global hacks. No mystery state.

---

## Terminal & Prompt

This repo configures a consistent terminal experience across hosts:

- **Kitty**
- **Alacritty**
- **Starship**
- **fastfetch / neofetch**

Themes and shared settings are broken into reusable fragments instead of copy-pasted blobs.

---

## Environment Variables

An `.env` file exists to document **structure**, not secrets.

Rules:

- ❌ Do not commit secrets
- ✅ Keep real values in a local, ignored env file
- ✅ Source env files explicitly

If you don’t know what a variable does, don’t set it.

---

## Installation (Intentional)

There is no one-line installer.

That’s deliberate.

Typical workflow:

```bash
git clone https://github.com/elikesbikes/linux_dotfiles.git ~/linux_dotfiles
cd ~/linux_dotfiles
```

From there:

- Read the files
- Symlink or copy what you actually want
- Leave the rest alone

Your system, your responsibility.

---

## Versioning & Stability

- `CHANGELOG.md` explains *why* things changed
- Git **tags** represent frozen, known-good states
- `main` is allowed to evolve

If you care about stability, **check out a tag**.

---

## Who This Is For

This repo is for:

- Linux power users
- Engineers, SREs, DevOps, homelabbers
- People who enjoy understanding their tools

If you want plug-and-play dotfiles, this probably isn’t it.

---

## License

Personal configuration repository.

Reuse what’s useful. Attribution appreciated.

---

## Final Note

These dotfiles match *my* brain and workflow.

Steal ideas, not assumptions.
