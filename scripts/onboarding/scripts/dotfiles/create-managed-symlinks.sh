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

detect_os() {
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    *)
      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        printf '%s' "${ID:-unknown}"
      else
        printf 'unknown'
      fi
      ;;
  esac
}

is_omarchy() {
  [[ -d /usr/share/omarchy ]] || [[ -d "$HOME_DIR/.config/omarchy" && ! -L "$HOME_DIR/.config/omarchy" ]]
}

is_macos() {
  [[ "$OS" == "macos" ]]
}

OS="$(detect_os)"
printf 'Detected OS: %s\n' "$OS"

if is_macos; then
  printf 'macOS detected — including macOS-specific links\n'
elif is_omarchy; then
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

  # If destination already resolves to the same real path as source (e.g.
  # a parent directory is symlinked into the repo), no link is needed.
  if [[ -e "$destination" && "$(readlink -f -- "$destination")" == "$(readlink -f -- "$source")" ]]; then
    printf 'ok      %s (via parent) -> %s\n' "$destination" "$source"
    return 0
  fi

  if [[ -L "$destination" ]]; then
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

# --- Common links (all platforms) ---

ensure_link "$HOME_DIR/.bash" "$REPO_DIR/.bash"
ensure_link "$HOME_DIR/.bashrc" "$REPO_DIR/.bashrc"
ensure_link "$HOME_DIR/scripts" "$REPO_DIR/scripts"

ensure_link "$HOME_DIR/.config/eza" "$REPO_DIR/.config/eza"
ensure_link "$HOME_DIR/.config/fastfetch" "$REPO_DIR/.config/fastfetch"
ensure_link "$HOME_DIR/.config/git" "$REPO_DIR/.config/git"
ensure_link "$HOME_DIR/.config/starship.toml" "$REPO_DIR/.config/starship.toml"

# Unison: symlink only profile files, not the whole directory.
# Runtime files (archives, fingerprints, logs) stay in the real ~/.unison/.
mkdir -p "$HOME_DIR/.unison"
for prf in "$REPO_DIR/.unison"/*.prf; do
  [[ -f "$prf" ]] || continue
  ensure_link "$HOME_DIR/.unison/$(basename "$prf")" "$prf"
done

# --- Linux-only common links ---

if ! is_macos; then
  ensure_link "$HOME_DIR/sudoers" "$REPO_DIR/sudoers"
  ensure_link "$HOME_DIR/.config/VeraCrypt" "$REPO_DIR/.config/VeraCrypt"
  ensure_link "$HOME_DIR/.config/neofetch" "$REPO_DIR/.config/neofetch"
fi

# --- Adastra repo (homelab docs, Claude skills, ubuntu working dir) ---

ADASTRA_DIR="$HOME_DIR/devops/github/adastra"
ADASTRA_URL="https://gitlab.home.elikesbikes.com/ecloaiza/adastra.git"

if [[ ! -d "$ADASTRA_DIR" ]]; then
  printf 'Adastra repository not found at %s — cloning...\n' "$ADASTRA_DIR"
  mkdir -p "$(dirname "$ADASTRA_DIR")"
  git clone "$ADASTRA_URL" "$ADASTRA_DIR"
else
  printf 'Pulling latest adastra changes...\n'
  git -C "$ADASTRA_DIR" pull --rebase || {
    printf 'Warning: adastra git pull failed — continuing with current checkout\n' >&2
  }
fi

# --- Claude Code (skills from adastra repo) ---

mkdir -p "$HOME_DIR/.claude"

ensure_link "$HOME_DIR/.claude/settings.json" "$REPO_DIR/.claude/settings.json"
ensure_link "$HOME_DIR/.claude/settings.local.json" "$REPO_DIR/.claude/settings.local.json"
ensure_link "$HOME_DIR/.claude/CLAUDE.md" "$REPO_DIR/.claude/CLAUDE.md"
ensure_link "$HOME_DIR/.claude/skills" "$ADASTRA_DIR/AI/skills"

# --- Devops ubuntu directory (Claude Code working directory, lives in adastra) ---

mkdir -p "$HOME_DIR/devops"
ensure_link "$HOME_DIR/devops/ubuntu" "$ADASTRA_DIR/AI/ubuntu"

# --- macOS-only links ---

if is_macos; then
  ensure_link "$HOME_DIR/.config/iterm2" "$REPO_DIR/.config/iterm2"
  ensure_link "$HOME_DIR/.config/kitty" "$REPO_DIR/.config/kitty"
fi

# --- Omarchy-only links (Hyprland, kitty, omarchy config) ---

if ! is_macos && is_omarchy; then
  ensure_link "$HOME_DIR/.config/hypr" "$REPO_DIR/.config/hypr"
  ensure_link "$HOME_DIR/.config/kitty" "$REPO_DIR/.config/kitty"
  ensure_link "$HOME_DIR/.config/omarchy/extensions" "$REPO_DIR/.config/omarchy/extensions"
  ensure_link "$HOME_DIR/.config/omarchy/hooks" "$REPO_DIR/.config/omarchy/hooks"
  ensure_link "$HOME_DIR/.config/omarchy/plugins" "$REPO_DIR/.config/omarchy/plugins"
  ensure_link "$HOME_DIR/.config/omarchy/shell.json" "$REPO_DIR/.config/omarchy/shell.json"
  ensure_link "$HOME_DIR/.config/omarchy/shell.toml" "$REPO_DIR/.config/omarchy/shell.toml"
fi
