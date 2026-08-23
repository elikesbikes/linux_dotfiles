# CLI

Daily-use command-line tools. This category does **not** run `apt update` (Core owns that).

## 1. Tools Installed

| Script | Tool | Source | Notes |
|--------|------|--------|-------|
| `install_neovim.sh` | Neovim | apt | Omakub-style; copies binary to `/usr/local/bin`; removes `tree-sitter-cli` |
| `install_starship.sh` | Starship prompt | official installer | Activated via dotfiles, not the installer |
| `install_direnv.sh` | direnv | apt | |
| `install_zoxide.sh` | zoxide | apt | |
| `install_stow.sh` | GNU Stow | apt | |
| `install_fastfetch.sh` | fastfetch | apt | |
| `install_figlet.sh` | figlet | apt | |
| `install_exa.sh` | exa (falls back to eza) | apt | `eza` is the modern replacement |
| `install_yazi.sh` | yazi | snap | Approved snap exception |
| `install_unison.sh` | unison | apt | File synchronizer |
| `install_build-essential.sh` | build-essential | apt | gcc/g++/make/libc-dev |

## 2. Notes

- No `apt update` is executed in this category
- Starship is activated via dotfiles, not the installer
- `install_neovim.sh` copies `/usr/bin/nvim` to `/usr/local/bin/nvim` so it wins on PATH
- `tree-sitter-cli` is explicitly removed after the Neovim install
- Each script is idempotent and writes a state marker under `~/.local/state/onboarding/installed/`

## 3. Verification

Run the audit-only check from the master menu (**Verify system → cli**) or directly:

```bash
bash ../verify/verify_cli.sh
```
