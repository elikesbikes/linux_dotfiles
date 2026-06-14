# Core

Foundational system setup. **Run this category first** — it refreshes apt and installs the base tooling every other category depends on.

## 1. Scripts

| Script | Installs | Source |
|--------|----------|--------|
| `install_sudo.sh` | Traditional `sudo` (TARS baseline; switches away from `sudo-rs`) | apt |
| `install_sudoers.sh` | Deploys sudoers drop-ins to `/etc/sudoers.d` (the `syncs` alias) | `sync-sudoers.sh` |
| `install_ssh.sh` | OpenSSH client | apt |
| `install_flatpak.sh` | Flatpak + Flathub remote | apt |
| `install_kitty.sh` | Kitty terminal + `kitty-terminfo` | apt |
| `install_default_editor.sh` | Sets system default `editor` alternative to nvim | `update-alternatives` |
| `install_node.sh` | Node.js + npm | apt |

## 2. Responsibilities

- Run `apt update` (Core is the **only** category allowed to refresh apt repositories)
- Ensure **traditional `sudo`** is the active implementation and report its version/plugin
  details. Ubuntu 25.10+ ships `sudo-rs` by default; `install_sudo.sh` detects it and
  switches the host back to classic sudo (via apt + the Debian alternatives system) because
  `sudo-rs` rejects directives our sudoers fragments use (`log_output`, `iolog_dir`,
  per-command `Defaults!`). TARS is the baseline.
- Deploy sudoers drop-in files to `/etc/sudoers.d` via `sync-sudoers.sh` (the `syncs` alias);
  requires `unison` (see `cli/install_unison.sh`) and the `~/.unison/sudoers.prf` profile from dotfiles
- Ensure the OpenSSH client is present
- Install Flatpak and configure the Flathub remote
- Install the Kitty terminal emulator and its terminfo entry
- Set the system default editor to nvim via the Debian `editor` alternative
  (fresh installs default to nano); requires nvim (`cli/install_neovim.sh`)
- Install Node.js and npm

## 3. Notes

- Each script is idempotent and writes a state marker under `~/.local/state/onboarding/installed/`
- Third-party repositories are added explicitly and intentionally
- `install_sudo.sh` falls back to bare `apt-get` if `sudo` is not yet present
- `kitty-terminfo` ships the `xterm-kitty` entry so SSH sessions from a Kitty
  terminal don't fail with "unknown terminal type"
