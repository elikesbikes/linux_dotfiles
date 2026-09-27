#!/usr/bin/env bash
set -euo pipefail

# Re-create the dotfiles symlink layout observed on this host.  This covers
# only intentional, repository-managed links at $HOME and directly under
# $HOME/.config; it deliberately excludes runtime/cache/application links.
#
# OS-aware: detects the running distro and only creates links that apply.
#   - Common links are created on every distro.
#   - Omarchy-specific links (hypr, omarchy, kitty) are skipped on non-Omarchy hosts.
#
# Each ensure_link call is independent (`|| true`): a single missing/renamed
# repo path or a pre-existing conflicting symlink is reported and skipped,
# not fatal to the rest of the script. (Regression fixed 2026-09: a stale
# reference to a since-removed .config/git repo path used to abort the whole
# script under `set -e`, silently skipping every link after it — including
# the .unison/*.prf profiles master.sh checks for.)

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

LINK_FAILURES=0

ensure_link() {
  local destination="$1"
  local source="$2"

  if [[ ! -e "$source" && ! -L "$source" ]]; then
    printf 'MISSING SOURCE — skipping: %s\n' "$source" >&2
    LINK_FAILURES=$((LINK_FAILURES + 1))
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
    LINK_FAILURES=$((LINK_FAILURES + 1))
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

ensure_link "$HOME_DIR/.bash" "$REPO_DIR/.bash" || true
ensure_link "$HOME_DIR/.bashrc" "$REPO_DIR/.bashrc" || true
ensure_link "$HOME_DIR/scripts" "$REPO_DIR/scripts" || true

ensure_link "$HOME_DIR/.config/eza" "$REPO_DIR/.config/eza" || true
ensure_link "$HOME_DIR/.config/fastfetch" "$REPO_DIR/.config/fastfetch" || true
ensure_link "$HOME_DIR/.config/starship.toml" "$REPO_DIR/.config/starship.toml" || true

# Unison: symlink only profile files, not the whole directory.
# Runtime files (archives, fingerprints, logs) stay in the real ~/.unison/.
mkdir -p "$HOME_DIR/.unison"
for prf in "$REPO_DIR/.unison"/*.prf; do
  [[ -f "$prf" ]] || continue
  ensure_link "$HOME_DIR/.unison/$(basename "$prf")" "$prf" || true
done

# --- Linux-only common links ---

if ! is_macos; then
  ensure_link "$HOME_DIR/sudoers" "$REPO_DIR/sudoers" || true
  # `icat` shim -> `kitten icat`: fastfetch's kitty-icat logo type expects a
  # binary literally named `icat`, which recent Kitty folded into `kitten
  # icat`. `kitten icat` has native tmux passthrough support, unlike
  # fastfetch's own `kitty` renderer — see .config/fastfetch/config.jsonc.
  mkdir -p "$HOME_DIR/.local/bin"
  ensure_link "$HOME_DIR/.local/bin/icat" "$REPO_DIR/.local/bin/icat" || true
  ensure_link "$HOME_DIR/.config/VeraCrypt" "$REPO_DIR/.config/VeraCrypt" || true
  ensure_link "$HOME_DIR/.config/neofetch" "$REPO_DIR/.config/neofetch" || true
fi

# --- Adastra repo (homelab docs, Claude skills, ubuntu working dir) ---

ADASTRA_DIR="$HOME_DIR/devops/github/adastra"
ADASTRA_URL="https://gitlab.home.elikesbikes.com/ecloaiza/adastra.git"

if [[ ! -d "$ADASTRA_DIR" ]]; then
  printf 'Adastra repository not found at %s — cloning...\n' "$ADASTRA_DIR"
  mkdir -p "$(dirname "$ADASTRA_DIR")"
  git clone "$ADASTRA_URL" "$ADASTRA_DIR" || {
    printf 'Warning: adastra clone failed (check GitLab credentials) — skipping adastra-dependent links\n' >&2
    LINK_FAILURES=$((LINK_FAILURES + 1))
  }
else
  printf 'Pulling latest adastra changes...\n'
  git -C "$ADASTRA_DIR" pull --rebase || {
    printf 'Warning: adastra git pull failed — continuing with current checkout\n' >&2
  }
fi

# --- Claude Code (skills from adastra repo) ---

mkdir -p "$HOME_DIR/.claude"

ensure_link "$HOME_DIR/.claude/settings.json" "$REPO_DIR/.claude/settings.json" || true
ensure_link "$HOME_DIR/.claude/settings.local.json" "$REPO_DIR/.claude/settings.local.json" || true
ensure_link "$HOME_DIR/.claude/CLAUDE.md" "$REPO_DIR/.claude/CLAUDE.md" || true
ensure_link "$HOME_DIR/.claude/skills" "$ADASTRA_DIR/AI/skills" || true
ensure_link "$HOME_DIR/.claude/hooks" "$REPO_DIR/.claude/hooks" || true

# --- Devops ubuntu directory (Claude Code working directory, lives in adastra) ---

mkdir -p "$HOME_DIR/devops"
ensure_link "$HOME_DIR/devops/ubuntu" "$ADASTRA_DIR/AI/ubuntu" || true

# --- macOS-only links ---

if is_macos; then
  ensure_link "$HOME_DIR/.config/iterm2" "$REPO_DIR/.config/iterm2" || true
  ensure_link "$HOME_DIR/.config/kitty" "$REPO_DIR/.config/kitty" || true
fi

# --- Omarchy-only links (Hyprland, kitty, omarchy config) ---

if ! is_macos && is_omarchy; then
  ensure_link "$HOME_DIR/.config/hypr" "$REPO_DIR/.config/hypr" || true
  ensure_link "$HOME_DIR/.config/kitty" "$REPO_DIR/.config/kitty" || true
  ensure_link "$HOME_DIR/.config/omarchy/extensions" "$REPO_DIR/.config/omarchy/extensions" || true
  ensure_link "$HOME_DIR/.config/omarchy/hooks" "$REPO_DIR/.config/omarchy/hooks" || true
  ensure_link "$HOME_DIR/.config/omarchy/plugins" "$REPO_DIR/.config/omarchy/plugins" || true
  ensure_link "$HOME_DIR/.config/omarchy/shell.json" "$REPO_DIR/.config/omarchy/shell.json" || true
  ensure_link "$HOME_DIR/.config/omarchy/shell.toml" "$REPO_DIR/.config/omarchy/shell.toml" || true
fi

# --- Summary ---

echo
if [[ "$LINK_FAILURES" -eq 0 ]]; then
  echo "All managed symlinks created successfully."
else
  echo "⚠ $LINK_FAILURES link(s) skipped — see MISSING SOURCE / conflict lines above." >&2
  echo "  This is not fatal (each failure is independent), but check them." >&2
fi
