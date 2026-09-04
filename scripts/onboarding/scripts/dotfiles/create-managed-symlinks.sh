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

REPO_URL="https://github.com/elikesbikes/linux_dotfiles"
GITLAB_URL="https://gitlab.home.elikesbikes.com/ecloaiza/linux_dotfiles.git"

if [[ ! -d "$REPO_DIR" ]]; then
  printf 'Dotfiles repository not found at %s — cloning...\n' "$REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
  git -C "$REPO_DIR" remote set-url --add --push origin "$REPO_URL"
  git -C "$REPO_DIR" remote set-url --add --push origin "$GITLAB_URL"
else
  printf 'Pulling latest changes...\n'
  git -C "$REPO_DIR" pull --rebase || {
    printf 'Warning: git pull failed — continuing with current checkout\n' >&2
  }
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

# Unison: symlink only profile files, not the whole directory.
# Runtime files (archives, fingerprints, logs) stay in the real ~/.unison/.
mkdir -p "$HOME_DIR/.unison"
for prf in "$REPO_DIR/.unison"/*.prf; do
  [[ -f "$prf" ]] || continue
  ensure_link "$HOME_DIR/.unison/$(basename "$prf")" "$prf"
done

# --- Claude Code (skills from adastra repo) ---

mkdir -p "$HOME_DIR/.claude"
mkdir -p "$REPO_DIR/.claude"

ensure_link "$HOME_DIR/.claude/settings.json" "$REPO_DIR/.claude/settings.json"
ensure_link "$HOME_DIR/.claude/settings.local.json" "$REPO_DIR/.claude/settings.local.json"
ensure_link "$HOME_DIR/.claude/CLAUDE.md" "$REPO_DIR/.claude/CLAUDE.md"

ADASTRA_SKILLS_DIR="$HOME_DIR/devops/github/adastra/AI/skills"
if [[ -d "$ADASTRA_SKILLS_DIR" ]]; then
  ensure_link "$HOME_DIR/.claude/skills" "$ADASTRA_SKILLS_DIR"
else
  printf 'Skipping .claude/skills — adastra repo not found at %s\n' "$ADASTRA_SKILLS_DIR"
fi

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
