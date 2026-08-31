#!/usr/bin/env bash
set -euo pipefail

# Re-create the dotfiles symlink layout observed on this host.  This covers
# only intentional, repository-managed links at $HOME and directly under
# $HOME/.config; it deliberately excludes runtime/cache/application links.
#
# OS-aware: detects the running distro and only creates links that apply.
#   - Common links are created on every distro.
#   - Omarchy-specific links (hypr, omarchy, kitty) are skipped on non-Omarchy hosts.

HOME_DIR="${HOME:-/home/ecloaiza}"
REPO_DIR="${DOTFILES_REPO_DIR:-$HOME_DIR/devops/github/linux_dotfiles}"
BACKUP_DIR="$HOME_DIR/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$REPO_DIR" ]]; then
  printf 'Dotfiles repository not found: %s\n' "$REPO_DIR" >&2
  exit 1
fi

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    printf '%s' "${ID:-unknown}"
  else
    printf 'unknown'
  fi
}

is_omarchy() {
  [[ -d /usr/share/omarchy ]] || [[ -d "$HOME_DIR/.config/omarchy" && ! -L "$HOME_DIR/.config/omarchy" ]]
}

DISTRO="$(detect_distro)"
printf 'Detected distro: %s\n' "$DISTRO"

if is_omarchy; then
  printf 'Omarchy detected — including Omarchy/Hyprland links\n'
else
  printf 'Non-Omarchy host — skipping Omarchy/Hyprland links\n'
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
    mkdir -p "$BACKUP_DIR"
    local backup_path="$BACKUP_DIR/$(basename "$destination")"
    cp -a -- "$destination" "$backup_path"
    printf 'backup  %s -> %s\n' "$destination" "$backup_path"
    rm -rf -- "$destination"
  fi

  ln -s -- "$source" "$destination"
  printf 'linked  %s -> %s\n' "$destination" "$source"
}

# --- Common links (all distros) ---

mkdir -p "$REPO_DIR/.bash"
mkdir -p "$REPO_DIR/.config/VeraCrypt"
mkdir -p "$REPO_DIR/.config/eza"
mkdir -p "$REPO_DIR/.config/fastfetch"
mkdir -p "$REPO_DIR/.config/neofetch"

ensure_link "$HOME_DIR/.bash" "$REPO_DIR/.bash"
ensure_link "$HOME_DIR/.bashrc" "$REPO_DIR/.bashrc"
ensure_link "$HOME_DIR/scripts" "$REPO_DIR/scripts"
ensure_link "$HOME_DIR/sudoers" "$REPO_DIR/sudoers"

ensure_link "$HOME_DIR/.config/VeraCrypt" "$REPO_DIR/.config/VeraCrypt"
ensure_link "$HOME_DIR/.config/eza" "$REPO_DIR/.config/eza"
ensure_link "$HOME_DIR/.config/fastfetch" "$REPO_DIR/.config/fastfetch"
ensure_link "$HOME_DIR/.config/neofetch" "$REPO_DIR/.config/neofetch"
ensure_link "$HOME_DIR/.config/starship.toml" "$REPO_DIR/.config/starship.toml"

# --- Omarchy-only links (Hyprland, kitty, omarchy config) ---

if is_omarchy; then
  mkdir -p "$REPO_DIR/.config/hypr"
  mkdir -p "$REPO_DIR/.config/kitty"
  mkdir -p "$REPO_DIR/.config/omarchy/extensions"
  mkdir -p "$REPO_DIR/.config/omarchy/hooks"
  mkdir -p "$REPO_DIR/.config/omarchy/plugins"

  ensure_link "$HOME_DIR/.config/hypr" "$REPO_DIR/.config/hypr"
  ensure_link "$HOME_DIR/.config/kitty" "$REPO_DIR/.config/kitty"
  ensure_link "$HOME_DIR/.config/omarchy/extensions" "$REPO_DIR/.config/omarchy/extensions"
  ensure_link "$HOME_DIR/.config/omarchy/hooks" "$REPO_DIR/.config/omarchy/hooks"
  ensure_link "$HOME_DIR/.config/omarchy/plugins" "$REPO_DIR/.config/omarchy/plugins"
  ensure_link "$HOME_DIR/.config/omarchy/shell.json" "$REPO_DIR/.config/omarchy/shell.json"
  ensure_link "$HOME_DIR/.config/omarchy/shell.toml" "$REPO_DIR/.config/omarchy/shell.toml"
fi
