# CLI Category

## Purpose
Terminal and developer tooling with standardized sources.

## Standardized sources
- APT: exa/eza, fastfetch, stow, zoxide, direnv, figlet
- Official installers: neovim, starship
- Snap (explicit exception): yazi

## What gets installed
- Neovim (official tarball to /opt, symlinked to /usr/local/bin)
- Starship (official installer to /usr/local/bin)
- Common CLI utilities via apt
- Yazi via snap

## What does NOT happen
- No shell configuration
- No dotfiles applied

## Scripts
- install_exa.sh
- install_fastfetch.sh
- install_neovim.sh
- install_stow.sh
- install_yazi.sh
- install_zoxide.sh
- install_starship.sh
- install_direnv.sh
- install_figlet.sh

## Notes
All scripts are idempotent and log to ~/.local/state/onboarding/logs.
