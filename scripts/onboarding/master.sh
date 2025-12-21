#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding/installed"

mkdir -p "$STATE_DIR"

# ------------------------------------------------------------
# Dry-run support
# ------------------------------------------------------------
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

# ------------------------------------------------------------
# Ensure gum is installed
# ------------------------------------------------------------
if ! command -v gum >/dev/null 2>&1; then
  echo "Installing gum..."
  sudo apt-get update
  sudo apt-get install -y gum
fi

# ------------------------------------------------------------
# UI helpers
# ------------------------------------------------------------
header() {
  gum style --bold --foreground 212 --border double --padding "1 2" "$1"
}

confirm() {
  gum confirm "$1"
}

# ------------------------------------------------------------
# Install category
# ------------------------------------------------------------
install_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ ! -d "$dir" ]] && return

  header "Installing: $category"

  for script in "$dir"/install_*.sh; do
    [[ -e "$script" ]] || continue
    chmod +x "$script"

    echo ""
    echo "→ Running $(basename "$script")"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY-RUN] $script"
    else
      "$script"
    fi
  done

  if [[ "$DRY_RUN" -eq 0 ]]; then
    touch "$STATE_DIR/$category"
  fi
}

# ------------------------------------------------------------
# Verify (state-aware)
# ------------------------------------------------------------
verify_installed() {
  header "Verification"

  for script in "$SCRIPTS_DIR/verify"/verify_*.sh; do
    [[ -e "$script" ]] || continue

    category="$(basename "$script" | sed 's/^verify_//; s/\.sh$//')"
    marker="$STATE_DIR/$category"

    if [[ ! -f "$marker" ]]; then
      echo "SKIP: $category (not installed)"
      continue
    fi

    chmod +x "$script"

    echo ""
    echo "→ Verifying $category"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY-RUN] $script"
    else
      "$script"
    fi
  done
}

# ------------------------------------------------------------
# Uninstall
# ------------------------------------------------------------
uninstall_menu() {
  header "Uninstall components"

  local choices
  choices=$(gum choose --no-limit cli desktop security back)

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return

    script="$SCRIPTS_DIR/cleanup/cleanup_${choice}.sh"
    [[ ! -f "$script" ]] && continue

    chmod +x "$script"

    if confirm "Uninstall $choice components?"; then
      echo ""
      echo "→ Uninstalling $choice"

      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DRY-RUN] $script"
      else
        "$script"
        rm -f "$STATE_DIR/$choice"
      fi
    fi
  done
}

# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------
while true; do
  header "Linux Dotfiles Onboarding"

  ACTION=$(gum choose \
    "Install components" \
    "Verify installation" \
    "Uninstall components" \
    "Exit")

  case "$ACTION" in
    "Install components")
      COMPONENTS=$(gum choose --no-limit core cli desktop security)

      [[ -z "$COMPONENTS" ]] && continue

      if confirm "Install selected components?"; then
        for component in $COMPONENTS; do
          install_category "$component"
        done
      fi
      ;;
    "Verify installation")
      verify_installed
      ;;
    "Uninstall components")
      uninstall_menu
      ;;
    "Exit")
      echo "Goodbye 👋"
      exit 0
      ;;
  esac
done
