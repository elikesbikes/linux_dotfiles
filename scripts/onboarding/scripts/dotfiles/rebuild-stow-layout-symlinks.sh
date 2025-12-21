#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$HOME/linux_dotfiles"
HOME_DIR="$HOME"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/tmp/stow-rebuild-symlinks-$TS"

echo "==> Rebuilding GNU Stow layout (SYMLINK SAFE)"
echo "==> Repo:   $REPO_DIR"
echo "==> Home:   $HOME_DIR"
echo "==> Backup: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

cd "$REPO_DIR"

#######################################
# helpers
#######################################
move_symlink_or_path() {
  local SRC="$1"
  local DEST="$2"

  # Ensure destination parent exists
  mkdir -p "$(dirname "$DEST")"

  if [ -L "$SRC" ]; then
    echo "    [symlink] $SRC -> $DEST"
    mv "$SRC" "$DEST"
  elif [ -e "$SRC" ]; then
    echo "    [path]    $SRC -> $DEST"
    mv "$SRC" "$DEST"
  else
    echo "    [skip]    $SRC not found"
  fi
}

#######################################
# 1. Create stow packages
#######################################
echo "==> Creating stow packages"
mkdir -p bash config tmux scripts sudoers

#######################################
# 2. Backup HOME (symlinks moved, targets untouched)
#######################################
echo "==> Backing up HOME paths (symlinks preserved)"

move_symlink_or_path "$HOME_DIR/.bash"       "$BACKUP_DIR/home/.bash"
move_symlink_or_path "$HOME_DIR/.config"     "$BACKUP_DIR/home/.config"
move_symlink_or_path "$HOME_DIR/exports"     "$BACKUP_DIR/home/exports"
move_symlink_or_path "$HOME_DIR/scripts"     "$BACKUP_DIR/home/scripts"
move_symlink_or_path "$HOME_DIR/sudoers"     "$BACKUP_DIR/home/sudoers"
move_symlink_or_path "$HOME_DIR/.bashrc"     "$BACKUP_DIR/home/.bashrc"
move_symlink_or_path "$HOME_DIR/.tmux.conf"  "$BACKUP_DIR/home/.tmux.conf"

# .env is backup-only, never stowed
move_symlink_or_path "$HOME_DIR/.env"        "$BACKUP_DIR/home/.env"

# IMPORTANT: remove/bypass omakub defaults bash path IF it is a symlink (or path)
# This prevents stow conflicts on .local/share/omakub/defaults/bash/*
move_symlink_or_path \
  "$HOME_DIR/.local/share/omakub/defaults/bash" \
  "$BACKUP_DIR/home/.local/share/omakub/defaults/bash"

#######################################
# 3. Move repo files INTO packages
#######################################
echo "==> Moving repo files into stow packages"

move_symlink_or_path "$REPO_DIR/.bashrc"  "$REPO_DIR/bash/.bashrc"
move_symlink_or_path "$REPO_DIR/exports"  "$REPO_DIR/bash/exports"

if [ -e "$REPO_DIR/.bash" ]; then
  move_symlink_or_path "$REPO_DIR/.bash"   "$REPO_DIR/bash/.bash"
fi

if [ -e "$REPO_DIR/.config" ]; then
  move_symlink_or_path "$REPO_DIR/.config" "$REPO_DIR/config/.config"
fi

move_symlink_or_path "$REPO_DIR/.tmux.conf" "$REPO_DIR/tmux/.tmux.conf"

#######################################
# 4. scripts & sudoers already packages
#######################################
echo "==> scripts/ and sudoers/ left as-is (already packages if present)"

#######################################
# 5. Dry run
#######################################
echo "==> Dry-run stow"
stow -n -v bash config tmux scripts sudoers

#######################################
# 6. Adopt + stow
#######################################
echo "==> Running stow --adopt"
stow --adopt bash config tmux scripts sudoers

echo
echo "==> DONE"
echo "Backup location: $BACKUP_DIR"
echo
echo "Suggested checks:"
echo "  tree -L 2 \"$REPO_DIR\""
echo "  ls -l \"$HOME_DIR\" | grep ' -> ' || true"
echo "  ls -ld \"$HOME_DIR/.local/share/omakub/defaults/bash\" || true"
echo "  git status"
echo "  git diff"
