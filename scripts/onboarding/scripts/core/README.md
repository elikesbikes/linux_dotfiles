# Core

Foundational system setup. **Run this category first** — it refreshes apt and installs the base tooling every other category depends on.

## 1. Scripts

| Script | Installs | Source |
|--------|----------|--------|
| `install_sudo.sh` | `sudo` (ensures present; reports `sudo -V`) | apt |
| `install_ssh.sh` | OpenSSH client | apt |
| `install_flatpak.sh` | Flatpak + Flathub remote | apt |
| `install_kitty.sh` | Kitty terminal + `kitty-terminfo` | apt |
| `install_node.sh` | Node.js + npm | apt |

## 2. Responsibilities

- Run `apt update` (Core is the **only** category allowed to refresh apt repositories)
- Ensure `sudo` is installed and report its version/plugin details
- Ensure the OpenSSH client is present
- Install Flatpak and configure the Flathub remote
- Install the Kitty terminal emulator and its terminfo entry
- Install Node.js and npm

## 3. Notes

- Each script is idempotent and writes a state marker under `~/.local/state/onboarding/installed/`
- Third-party repositories are added explicitly and intentionally
- `install_sudo.sh` falls back to bare `apt-get` if `sudo` is not yet present
- `kitty-terminfo` ships the `xterm-kitty` entry so SSH sessions from a Kitty
  terminal don't fail with "unknown terminal type"
