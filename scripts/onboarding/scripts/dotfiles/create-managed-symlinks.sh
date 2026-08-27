#!/usr/bin/env bash
set -euo pipefail

# Re-create the dotfiles symlink layout observed on this host.  This covers
# only intentional, repository-managed links at $HOME and directly under
# $HOME/.config; it deliberately excludes runtime/cache/application links.

HOME_DIR="${HOME:-/home/ecloaiza}"
REPO_DIR="${DOTFILES_REPO_DIR:-$HOME_DIR/devops/github/linux_dotfiles}"

if [[ ! -d "$REPO_DIR" ]]; then
  printf 'Dotfiles repository not found: %s\n' "$REPO_DIR" >&2
  exit 1
fi

ensure_link() {
  local destination="$1"
  local source="$2"

  if [[ ! -e "$source" && ! -L "$source" ]]; then
    printf 'Source is missing; refusing to link: %s\n' "$source" >&2
    return 1
  fi

  mkdir -p "$(dirname "$destination")"

  if [[ -L "$destination" ]]; then
    if [[ "$(readlink -f -- "$destination")" == "$(readlink -f -- "$source")" ]]; then
      printf 'ok      %s -> %s\n' "$destination" "$source"
      return 0
    fi

    printf 'conflict %s already links to %s\n' "$destination" "$(readlink -- "$destination")" >&2
    return 1
  fi

  if [[ -e "$destination" ]]; then
    printf 'conflict %s already exists and is not a symlink\n' "$destination" >&2
    return 1
  fi

  ln -s -- "$source" "$destination"
  printf 'linked  %s -> %s\n' "$destination" "$source"
}

ensure_link "$HOME_DIR/.bash" "$REPO_DIR/.bash"
ensure_link "$HOME_DIR/.bashrc" "$REPO_DIR/.bashrc"
ensure_link "$HOME_DIR/scripts" "$REPO_DIR/scripts"
ensure_link "$HOME_DIR/sudoers" "$REPO_DIR/sudoers"

ensure_link "$HOME_DIR/.config/VeraCrypt" "$REPO_DIR/.config/VeraCrypt"
ensure_link "$HOME_DIR/.config/eza" "$REPO_DIR/.config/eza"
ensure_link "$HOME_DIR/.config/fastfetch" "$REPO_DIR/.config/fastfetch"
ensure_link "$HOME_DIR/.config/kitty" "$REPO_DIR/.config/kitty"
ensure_link "$HOME_DIR/.config/neofetch" "$REPO_DIR/.config/neofetch"
ensure_link "$HOME_DIR/.config/starship.toml" "$REPO_DIR/.config/starship.toml"
