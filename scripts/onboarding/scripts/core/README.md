# Core

Foundational system setup. **Run this category first** — it refreshes apt and installs the base tooling every other category depends on.

## 1. Scripts

| Script | Installs | Source |
|--------|----------|--------|
| `install_sudo.sh` | Traditional `sudo` (TARS baseline; switches away from `sudo-rs`) | apt |
| `install_ssh.sh` | OpenSSH client | apt |
| `install_flatpak.sh` | Flatpak + Flathub remote | apt |
| `install_kitty.sh` | Kitty terminal + `kitty-terminfo` + `imagemagick` | apt |
| `install_node.sh` | Node.js + npm | apt |
| `install_motd.sh` | Disables Ubuntu's dynamic MOTD (news/ads, ESM/Pro nags, sysinfo block) on SSH login | `/etc/update-motd.d`, `/etc/default/motd-news` |

Sudoers drop-ins (`cli/install_zz_sudoers.sh`) and the default-editor alternative
(`cli/install_zz_default_editor.sh`) live in the `cli` category, not here — see
`cli/README.md`.

## 2. Responsibilities

- Run `apt update` (Core is the **only** category allowed to refresh apt repositories)
- Ensure **traditional `sudo`** is the active implementation and report its version/plugin
  details. Ubuntu 25.10+ ships `sudo-rs` by default; `install_sudo.sh` detects it and
  switches the host back to classic sudo (via apt + the Debian alternatives system) because
  `sudo-rs` rejects directives our sudoers fragments use (`log_output`, `iolog_dir`,
  per-command `Defaults!`). TARS is the baseline.
- Ensure the OpenSSH client is present
- Install Flatpak and configure the Flathub remote
- Install the Kitty terminal emulator, its terminfo entry, and `imagemagick`
  (kitty's own optional dependency for `kitten icat`, needed for image rendering
  in the terminal — e.g. fastfetch's `kitty-icat` logo type shells out to it)
- Install Node.js and npm
- Disable Ubuntu's dynamic MOTD (`update-motd.d` fragments + `motd-news`) so SSH logins
  show only the static "Welcome to Ubuntu ..." line, not the load/memory/IP block, news
  fetch, or ESM/Pro ads. Debian/Ubuntu-only; a clean no-op elsewhere (e.g. tars/Omarchy).

Sudoers drop-in deployment and the default-editor alternative are handled later in the
`cli` category (they depend on `unison` and `nvim`, both installed there) — see
`cli/README.md`.

## 3. Notes

- Each script is idempotent and writes a state marker under `~/.local/state/onboarding/installed/`
- Third-party repositories are added explicitly and intentionally
- `install_sudo.sh` falls back to bare `apt-get` if `sudo` is not yet present
- `kitty-terminfo` ships the `xterm-kitty` entry so SSH sessions from a Kitty
  terminal don't fail with "unknown terminal type"
