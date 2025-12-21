# Dotfiles Bootstrap

Contains the bootstrap logic for new hosts.

## install_dotfiles.sh

Behavior:
- Runs from $HOME (never from inside the repo)
- Force-removes any existing dotfiles checkout
- Clones the repository fresh
- Removes Omakub bash defaults
- Removes ~/.bashrc to allow Stow ownership
- Runs `stow . -t ~`
- Launches onboarding

## Safety
- Never deletes the current working directory
- Fails loudly on unresolved Stow conflicts
