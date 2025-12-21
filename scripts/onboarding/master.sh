#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/onboarding"
LOG_DIR="$STATE_DIR/logs"
INSTALLED_DIR="$STATE_DIR/installed"

mkdir -p "$LOG_DIR" "$INSTALLED_DIR"

# --------------------------------------------------
# Utilities
# --------------------------------------------------
ts() { date +"%a %b %d %I:%M:%S %p %Z %Y"; }

log() {
  echo "$1"
}

run_script() {
  local script="$1"
  chmod +x "$script"
  "$script"
}

# --------------------------------------------------
# Ensure gum (Charm repo, Omakub-style)
# --------------------------------------------------
ensure_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  echo "Installing gum (Charm repo)..."

  sudo apt-get update
  sudo apt-get install -y curl ca-certificates gnupg

  sudo install -d -m 0755 /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/charm.gpg ]]; then
    curl -fsSL https://repo.charm.sh/apt/gpg.key \
      | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/charm.list ]]; then
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
      | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
  fi

  sudo apt-get update
  sudo apt-get install -y gum
}

# --------------------------------------------------
# Category execution
# --------------------------------------------------
run_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  [[ -d "$dir" ]] || return 0

  gum style --border normal --padding "1 2" "Installing: $category"

  for script in "$dir"/install_*.sh; do
    [[ -f "$script" ]] || continue
    echo "→ Running $(basename "$script")"
    run_script "$script"
  done

  touch "$INSTALLED_DIR/$category"
}

verify_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  gum style --border normal --padding "1 2" "VERIFY: $category"

  for script in "$dir"/verify_*.sh; do
    [[ -f "$script" ]] || continue
    run_script "$script"
  done
}

uninstall_category() {
  local category="$1"
  local dir="$SCRIPTS_DIR/$category"

  gum style --border normal --padding "1 2" "UNINSTALL: $category"

  for script in "$dir"/uninstall_*.sh; do
    [[ -f "$script" ]] || continue
    run_script "$script"
  done

  rm -f "$INSTALLED_DIR/$category"
}

# --------------------------------------------------
# Menus
# --------------------------------------------------
install_menu() {
  local choices
  choices=$(printf "core\ncli\ndesktop\nsecurity\nback" | gum choose --no-limit)

  [[ -z "$choices" ]] && return

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return
    run_category "$choice"
  done
}

verify_menu() {
  local choices
  choices=$(printf "core\ncli\ndesktop\nsecurity\nback" | gum choose --no-limit)

  [[ -z "$choices" ]] && return

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return
    verify_category "$choice"
  done
}

uninstall_menu() {
  local choices
  choices=$(printf "core\ncli\ndesktop\nsecurity\nback" | gum choose --no-limit)

  [[ -z "$choices" ]] && return

  for choice in $choices; do
    [[ "$choice" == "back" ]] && return
    uninstall_category "$choice"
  done
}

# --------------------------------------------------
# Main menu
# --------------------------------------------------
main_menu() {
  while true; do
    gum style --border double --padding "1 4" "Linux Dotfiles Onboarding"

    choice=$(printf "Install components\nVerify system\nUninstall components\nExit\n" \
      | gum choose)

    case "$choice" in
      "Install components") install_menu ;;
      "Verify system") verify_menu ;;
      "Uninstall components") uninstall_menu ;;
      "Exit") exit 0 ;;
    esac
  done
}

# --------------------------------------------------
# Entry
# --------------------------------------------------
ensure_gum
main_menu
