# Dotfiles Bootstrap

Bootstrap logic for new hosts plus a helper to rebuild the GNU Stow package layout.

## 1. install_dotfiles.sh

The entry point invoked by the one-line bootstrap. Behavior:

- Runs from `$HOME` (never from inside the repo it may delete)
- Force-removes any existing checkout at `~/devops/github/linux_dotfiles`
- Installs `git` and `stow`
- Clones the repository fresh from GitHub
- Re-adds the GitLab push URL on `origin` (a fresh clone only knows GitHub), so
  later commits reach both remotes and trigger GitLab CI
- Removes Omakub bash defaults to avoid Stow conflicts
- Removes `~/.bashrc` so the Stow-managed version can own it
- Runs `stow . -t ~`
- Launches the onboarding master menu

### Safety
- Never deletes the current working directory
- Fails loudly (`set -euo pipefail`) on unresolved Stow conflicts

## 2. rebuild-stow-layout-symlinks.sh

Reorganizes the repo into Stow packages (`bash`, `config`, `tmux`, `scripts`, `sudoers`) and re-stows them, backing up existing HOME paths first.

- Repo location defaults to `~/devops/github/linux_dotfiles`
- Override with `DOTFILES_REPO_DIR=/path bash rebuild-stow-layout-symlinks.sh`
- Symlinks are moved (targets untouched); originals backed up to `/tmp/stow-rebuild-symlinks-<timestamp>`
- Performs a `stow -n` dry-run before `stow --adopt`

## 3. Notes

- Logs are written under `~/.local/state/onboarding/logs/`
- Both scripts are intended to run on a Debian/Ubuntu host with `apt`
