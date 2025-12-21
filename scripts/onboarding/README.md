# Linux Dotfiles Onboarding

This repository provides a complete, idempotent onboarding system for Linux hosts.
It installs system software, CLI tools, desktop applications, and security tooling,
then deploys user configuration via GNU Stow.

## One-line bootstrap (new host)

```bash
wget -qO- https://raw.githubusercontent.com/elikesbikes/linux_dotfiles/refs/heads/main/scripts/onboarding/scripts/dotfiles/install_dotfiles.sh | bash
```

This will:
- Force-clone the dotfiles repository
- Install GNU Stow
- Remove known conflicting files (including ~/.bashrc)
- Deploy dotfiles using `stow . -t ~`
- Launch the interactive onboarding menu

## Design principles

- Core owns `apt update`
- CLI scripts do not modify repositories
- gum is used only for UX (no hidden execution)
- All installs are idempotent
- Category installs are state-tracked
- Configuration is managed exclusively via dotfiles
