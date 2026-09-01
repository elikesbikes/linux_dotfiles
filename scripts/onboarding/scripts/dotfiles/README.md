# Dotfiles Bootstrap

Bootstrap logic for new hosts plus a helper to rebuild the GNU Stow package layout.

## 1. create-managed-symlinks.sh

The primary dotfiles entry point. Behavior:

- If the repo is missing at `~/devops/github/linux_dotfiles`, clones it from GitHub
  and configures dual-remote push (GitHub + GitLab)
- If the repo exists, pulls the latest changes before proceeding
- Creates symlinks from `$HOME` into the repo for all managed dotfiles
- OS-aware: detects Omarchy and only creates Hyprland/kitty/omarchy links on
  Omarchy hosts
- Backs up any existing files before replacing them with symlinks
- Idempotent — safe to re-run at any time

```bash
bash scripts/onboarding/scripts/dotfiles/create-managed-symlinks.sh
```

Set `DOTFILES_REPO_DIR` to use a checkout outside the default location.

## 2. Notes

- Logs are written under `~/.local/state/onboarding/logs/`
- Both scripts are intended to run on a Debian/Ubuntu host with `apt`
